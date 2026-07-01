defmodule Bob.DockerHub.RateLimiter do
  @moduledoc """
  Process-wide gate that lets Docker Hub API requests burst up to the window's
  limit, then waits for the window to reset. Docker Hub caps the tags API at 600
  requests/minute per source IP and reports the budget in its `x-ratelimit-*`
  headers.

  The count is of **our own** granted requests, not the server's reported
  `remaining` — that number lags the requests already in flight, so granting up
  to it overshoots. `remaining` is used only to seed the count (so a window the
  previous run partly spent is respected) and to ratchet it up if something
  outside this process eats budget; it never lowers our own tally. The window is
  reset on a timer derived from the `reset` header plus a small offset, so we
  resume only after the server's window has actually rolled — not a beat before
  it, when our clock runs slightly ahead of Docker Hub's.

  A request sent before any response has anchored the window is the lone
  calibration probe. The gate reclaims its slot if it reports a response
  without usable rate headers, or dies without reporting at all, so a probe
  that never anchors the window can't wedge every later caller behind it
  forever.
  """

  use GenServer

  require Logger

  # Resume this long after the server's reset, so a local clock running slightly
  # ahead of Docker Hub's can't send into the tail of the previous window.
  @resume_offset_ms 2_000

  # How long to hold the gate shut on a 429 that carries no usable rate headers,
  # so callers stop hammering until the server's limit has had time to reset.
  @throttle_fallback_ms 60_000

  def start_link(opts \\ []) do
    case Keyword.get(opts, :name, __MODULE__) do
      nil -> GenServer.start_link(__MODULE__, opts)
      name -> GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  @doc "Blocks until a request may be sent under the current window's budget."
  def acquire(server \\ __MODULE__) do
    GenServer.call(server, :acquire, :infinity)
  end

  @doc """
  Feeds a response's headers back so the gate tracks the limit and window.
  Callers report every completed request, headers or not (`[]` for a transport
  error): a report without usable rate headers releases the calibration
  probe's slot when it comes from the probe itself, since that request
  finished without anchoring the window.
  """
  def observe(headers, server \\ __MODULE__) do
    GenServer.cast(server, {:observe, parse_rate(headers), self()})
  end

  @doc """
  Feeds a 429 response back so the gate holds shut until the limit window
  resets. If the response carries rate headers we anchor on their `reset`;
  otherwise we fall back to a fixed wait.
  """
  def throttle(headers, server \\ __MODULE__) do
    GenServer.cast(server, {:throttle, parse_rate(headers)})
  end

  @doc false
  def parse_rate(headers) do
    headers = Map.new(headers, fn {key, value} -> {String.downcase(key), value} end)

    with {:ok, limit} <- fetch_int(headers, "x-ratelimit-limit"),
         {:ok, remaining} <- fetch_int(headers, "x-ratelimit-remaining"),
         {:ok, reset} <- fetch_int(headers, "x-ratelimit-reset") do
      %{limit: limit, remaining: remaining, reset: reset}
    else
      _ -> nil
    end
  end

  @impl true
  def init(opts) do
    {:ok,
     %{
       sent: 0,
       limit: nil,
       window: nil,
       reset_at: nil,
       offset_ms: Keyword.get(opts, :offset_ms, @resume_offset_ms),
       timer: nil,
       probe_mon: nil,
       probe_pid: nil,
       waiters: :queue.new()
     }}
  end

  @impl true
  def handle_call(:acquire, from, state) do
    state = roll(state)

    if available?(state) do
      {:reply, :ok, grant(state, from)}
    else
      {:noreply, schedule_resume(%{state | waiters: :queue.in(from, state.waiters)})}
    end
  end

  # The probe finished without usable rate headers, so nothing anchored the
  # window: reclaim its slot the same way its death would, or the gate stays
  # shut when the probe runs in a long-lived process.
  @impl true
  def handle_cast({:observe, nil, pid}, %{probe_pid: pid} = state) do
    {:noreply, schedule_resume(release(reclaim_probe(state)))}
  end

  def handle_cast({:observe, nil, _pid}, state), do: {:noreply, state}

  def handle_cast({:observe, rate, _pid}, state) do
    state = apply_rate(state, rate)
    state = if state.window != nil, do: clear_probe_mon(state), else: state
    {:noreply, schedule_resume(release(state))}
  end

  # A 429 with rate headers reports remaining == 0, so apply_rate anchors the
  # window with the count maxed out and the gate stays shut until it resets. No
  # release: there is nothing to hand out.
  def handle_cast({:throttle, rate}, state) when not is_nil(rate) do
    state = clear_probe_mon(apply_rate(state, rate))
    log_throttle(state)
    {:noreply, schedule_resume(state)}
  end

  # A 429 without usable headers: hold the window shut for a fixed spell.
  def handle_cast({:throttle, nil}, state) do
    state = clear_probe_mon(park(state, @throttle_fallback_ms))
    log_throttle(state)
    {:noreply, schedule_resume(state)}
  end

  @impl true
  def handle_info(:resume, state) do
    {:noreply, schedule_resume(release(roll(%{state | timer: nil})))}
  end

  # The calibration probe died. If it never anchored the window, reclaim its
  # slot and wake the next caller, so a probe that failed to report a response
  # can't leave the gate shut with nothing left to roll or release it.
  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{probe_mon: ref} = state) do
    {:noreply, schedule_resume(release(reclaim_probe(state)))}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    {:noreply, state}
  end

  # No confirmed window yet (cold start, or just rolled): allow a single probe
  # so the next response anchors the real budget before we burst into it.
  defp available?(%{window: nil, sent: sent}), do: sent < 1
  defp available?(%{sent: sent, limit: limit}), do: sent < limit

  # Hands a slot to `from`. While the window is unanchored the granted request is
  # the lone calibration probe — monitor it so its termination can reclaim the
  # slot if it dies without anchoring the window.
  defp grant(state, from) do
    state = %{state | sent: state.sent + 1}

    if state.window == nil and state.probe_mon == nil do
      pid = elem(from, 0)
      %{state | probe_mon: Process.monitor(pid), probe_pid: pid}
    else
      state
    end
  end

  # The probe finished without anchoring the window: give its slot back so the
  # next caller becomes the new probe.
  defp reclaim_probe(state) do
    state = clear_probe_mon(state)
    if state.window == nil, do: %{state | sent: max(state.sent - 1, 0)}, else: state
  end

  # Stop tracking the calibration probe once the window is anchored; its eventual
  # exit no longer tells us anything.
  defp clear_probe_mon(%{probe_mon: nil} = state), do: state

  defp clear_probe_mon(%{probe_mon: ref} = state) do
    Process.demonitor(ref, [:flush])
    %{state | probe_mon: nil, probe_pid: nil}
  end

  # Folds a response's rate headers into the window: anchor it on the window's
  # first response and seed the count from the server's usage; on later
  # responses only ratchet the count up, never lower our own tally.
  defp apply_rate(state, %{limit: limit, remaining: remaining, reset: reset}) do
    state = %{state | limit: limit}

    cond do
      state.window == nil ->
        %{
          state
          | window: reset,
            reset_at: monotonic_deadline(reset) + state.offset_ms,
            sent: max(state.sent, limit - remaining)
        }

      reset == state.window ->
        %{state | sent: max(state.sent, limit - remaining)}

      true ->
        state
    end
  end

  # Force the gate shut for `ms`, regardless of what the window thought it had.
  defp park(state, ms) do
    limit = state.limit || 1

    %{
      state
      | limit: limit,
        sent: limit,
        window: state.window || :throttled,
        reset_at: System.monotonic_time(:millisecond) + ms + state.offset_ms
    }
  end

  # The window has elapsed (its reset plus the offset has passed): start the next
  # one with a clean count. The next response re-anchors the window.
  defp roll(%{reset_at: reset_at} = state) when not is_nil(reset_at) do
    if System.monotonic_time(:millisecond) >= reset_at do
      %{state | sent: 0, window: nil, reset_at: nil}
    else
      state
    end
  end

  defp roll(state), do: state

  defp release(state) do
    cond do
      not available?(state) ->
        state

      :queue.is_empty(state.waiters) ->
        state

      true ->
        {{:value, from}, waiters} = :queue.out(state.waiters)
        GenServer.reply(from, :ok)
        release(grant(%{state | waiters: waiters}, from))
    end
  end

  # Wake at the window's reset so parked callers are released even when no further
  # responses arrive to drive observe.
  defp schedule_resume(%{timer: nil, reset_at: reset_at, waiters: waiters} = state)
       when not is_nil(reset_at) do
    if :queue.is_empty(waiters) do
      state
    else
      delay = max(reset_at - System.monotonic_time(:millisecond), 0)
      %{state | timer: Process.send_after(self(), :resume, delay)}
    end
  end

  defp schedule_resume(state), do: state

  defp log_throttle(%{reset_at: reset_at}) do
    wait_s = div(max(reset_at - System.monotonic_time(:millisecond), 0), 1000)
    Logger.warning("DockerHub rate limited, holding #{wait_s}s for the window to reset")
  end

  defp monotonic_deadline(reset_unix) do
    delay_ms = max(reset_unix - System.os_time(:second), 0) * 1000
    System.monotonic_time(:millisecond) + delay_ms
  end

  defp fetch_int(headers, key) do
    case headers do
      %{^key => value} ->
        case Integer.parse(value) do
          {int, _} -> {:ok, int}
          :error -> :error
        end

      _ ->
        :error
    end
  end
end
