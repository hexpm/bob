defmodule Bob.DockerHub.RateLimiter do
  @moduledoc """
  Process-wide gate that paces Docker Hub API requests under the account's
  budget.

  Docker Hub meters a rolling window: `x-ratelimit-reset` is a moving estimate
  of when the oldest request ages out, recomputed on every response, not a
  boundary the count resets on. The gate keeps its own send times and admits
  while fewer than `limit` of them fall in the trailing window, the model the
  server applies.

  The budget is metered per account rather than per source IP, so other nodes
  spend it too. `x-ratelimit-remaining` carries that across them: when another
  node spends, this one sees the budget fall and backs off, with no shared
  state. It is read against the requests still in flight, which the server has
  not counted yet, and dropped once it is older than the window it was taken in.

  Every granted caller is monitored so one that dies without reporting gives its
  slot back.
  """

  use GenServer

  require Logger

  # Docker Hub meters a rolling minute; our own sends are held for as long, so
  # the trailing count lines up with what the server is counting.
  @window_ms 60_000

  # How long the gate stays shut after a 429, giving the window time to move
  # before the caller retries.
  @park_ms 5_000

  def start_link(opts \\ []) do
    case Keyword.get(opts, :name, __MODULE__) do
      nil -> GenServer.start_link(__MODULE__, opts)
      name -> GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  @doc "Blocks until a request may be sent under the account's budget."
  def acquire(server \\ __MODULE__) do
    GenServer.call(server, :acquire, :infinity)
  end

  @doc """
  Feeds a response's headers back so the gate tracks the budget and releases the
  slot the caller took. Callers report every completed request, headers or not
  (`[]` for a transport error).
  """
  def observe(headers, server \\ __MODULE__) do
    GenServer.cast(server, {:observe, parse_rate(headers), self()})
  end

  @doc "Feeds a 429 back so the gate holds shut and stops the caller retrying into it."
  def throttle(headers, server \\ __MODULE__) do
    GenServer.cast(server, {:throttle, parse_rate(headers), self()})
  end

  @doc false
  def parse_rate(headers) do
    headers = Map.new(headers, fn {key, value} -> {String.downcase(key), value} end)

    with {:ok, limit} <- fetch_int(headers, "x-ratelimit-limit"),
         {:ok, remaining} <- fetch_int(headers, "x-ratelimit-remaining") do
      %{limit: limit, remaining: remaining}
    else
      _ -> nil
    end
  end

  @impl true
  def init(opts) do
    {:ok,
     %{
       limit: nil,
       remaining: nil,
       measured_at: nil,
       sends: :queue.new(),
       in_flight: 0,
       holders: %{},
       parked_until: nil,
       waiters: :queue.new(),
       timer: nil,
       window_ms: Keyword.get(opts, :window_ms, @window_ms),
       park_ms: Keyword.get(opts, :park_ms, @park_ms),
       clock: Keyword.get(opts, :clock, &__MODULE__.monotonic_ms/0)
     }}
  end

  @doc false
  def monotonic_ms(), do: System.monotonic_time(:millisecond)

  @impl true
  def handle_call(:acquire, from, state) do
    state = expire(state)

    if available?(state) do
      {:reply, :ok, grant(state, elem(from, 0))}
    else
      {:noreply, schedule(%{state | waiters: :queue.in(from, state.waiters)})}
    end
  end

  @impl true
  def handle_cast({:observe, rate, pid}, state) do
    state = state |> release_slot(pid) |> apply_rate(rate) |> expire()
    {:noreply, schedule(admit(state))}
  end

  def handle_cast({:throttle, rate, pid}, state) do
    state = state |> release_slot(pid) |> apply_rate(rate) |> expire()
    state = %{state | parked_until: state.clock.() + state.park_ms}

    Logger.warning(
      "DockerHub rate limited, holding #{div(state.park_ms, 1000)}s before sending again"
    )

    {:noreply, schedule(state)}
  end

  @impl true
  def handle_info(:wake, state) do
    {:noreply, schedule(admit(expire(%{state | timer: nil})))}
  end

  # A caller died mid-request and will never report, so return every slot it
  # held.
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    state =
      case state.holders do
        %{^pid => {_ref, held}} ->
          %{state | holders: Map.delete(state.holders, pid), in_flight: state.in_flight - held}

        _ ->
          state
      end

    {:noreply, schedule(admit(expire(state)))}
  end

  # Until the budget has been measured, or once the measurement has aged out of
  # the window, one request goes on its own to establish it.
  defp available?(%{parked_until: parked}) when not is_nil(parked), do: false
  defp available?(%{remaining: nil} = state), do: state.in_flight == 0

  defp available?(state) do
    :queue.len(state.sends) < state.limit and state.remaining > state.in_flight
  end

  defp grant(state, pid) do
    holders =
      case state.holders do
        %{^pid => {ref, held}} -> Map.put(state.holders, pid, {ref, held + 1})
        _ -> Map.put(state.holders, pid, {Process.monitor(pid), 1})
      end

    %{
      state
      | sends: :queue.in(state.clock.(), state.sends),
        in_flight: state.in_flight + 1,
        holders: holders
    }
  end

  defp release_slot(state, pid) do
    case state.holders do
      %{^pid => {ref, 1}} ->
        Process.demonitor(ref, [:flush])
        %{state | holders: Map.delete(state.holders, pid), in_flight: state.in_flight - 1}

      %{^pid => {ref, held}} ->
        holders = Map.put(state.holders, pid, {ref, held - 1})
        %{state | holders: holders, in_flight: state.in_flight - 1}

      _ ->
        state
    end
  end

  # The newest reading wins, so a budget that has recovered is seen as recovered.
  defp apply_rate(state, nil), do: state

  defp apply_rate(state, %{limit: limit, remaining: remaining}) do
    %{state | limit: limit, remaining: remaining, measured_at: state.clock.()}
  end

  # Ages out the sends that have left the window, the park, and a reading taken
  # in a window that has since rolled.
  defp expire(state) do
    now = state.clock.()
    cutoff = now - state.window_ms
    stale? = state.measured_at != nil and state.measured_at <= cutoff

    %{
      state
      | sends: drop_before(state.sends, cutoff),
        parked_until: if(parked?(state.parked_until, now), do: state.parked_until),
        remaining: if(stale?, do: nil, else: state.remaining),
        measured_at: if(stale?, do: nil, else: state.measured_at)
    }
  end

  defp parked?(nil, _now), do: false
  defp parked?(parked_until, now), do: now < parked_until

  defp drop_before(sends, cutoff) do
    case :queue.peek(sends) do
      {:value, at} when at <= cutoff -> sends |> :queue.drop() |> drop_before(cutoff)
      _ -> sends
    end
  end

  defp admit(state) do
    if available?(state) and not :queue.is_empty(state.waiters) do
      {{:value, from}, waiters} = :queue.out(state.waiters)
      GenServer.reply(from, :ok)
      admit(grant(%{state | waiters: waiters}, elem(from, 0)))
    else
      state
    end
  end

  # Wake at the next moment the gate could open on its own.
  defp schedule(state) do
    state = cancel_timer(state)

    with false <- :queue.is_empty(state.waiters),
         at when not is_nil(at) <- wake_at(state) do
      delay = max(at - state.clock.(), 0)
      %{state | timer: Process.send_after(self(), :wake, delay)}
    else
      _ -> state
    end
  end

  defp wake_at(state) do
    oldest_send =
      case :queue.peek(state.sends) do
        {:value, at} -> at + state.window_ms
        :empty -> nil
      end

    measurement = state.measured_at && state.measured_at + state.window_ms

    [state.parked_until, oldest_send, measurement]
    |> Enum.reject(&is_nil/1)
    |> Enum.min(fn -> nil end)
  end

  defp cancel_timer(%{timer: nil} = state), do: state

  defp cancel_timer(%{timer: timer} = state) do
    Process.cancel_timer(timer)
    %{state | timer: nil}
  end

  defp fetch_int(headers, key) do
    case headers do
      %{^key => value} ->
        case Integer.parse(value) do
          {int, _rest} -> {:ok, int}
          :error -> :error
        end

      _ ->
        :error
    end
  end
end
