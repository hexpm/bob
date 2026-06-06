defmodule Bob.DockerHub.RateLimiter do
  @moduledoc """
  Process-wide gate that paces Docker Hub API requests to the budget Docker Hub
  reports in its `x-ratelimit-*` headers (600/min, keyed by source IP).

  Every request calls `acquire/1` before sending and `observe/2` after. `acquire`
  is an atomic check-and-count against the window's limit — it runs inside this
  GenServer, so no two callers race past the ceiling, and no safety buffer is
  needed: we count our own requests exactly. The server's reported `remaining` is
  folded in only to raise our count (catching any usage from outside this
  process), keyed by the window's `reset` so a stale, out-of-order response can't
  corrupt the next window. Tracking this in one process keeps it correct across
  repos and every other caller sharing the IP's budget.
  """

  use GenServer

  def start_link(opts \\ []) do
    case Keyword.get(opts, :name, __MODULE__) do
      nil -> GenServer.start_link(__MODULE__, [])
      name -> GenServer.start_link(__MODULE__, [], name: name)
    end
  end

  @doc "Blocks until a Docker Hub request may be sent under the current budget."
  def acquire(server \\ __MODULE__) do
    GenServer.call(server, :acquire, :infinity)
  end

  @doc "Feeds a response's headers back so the gate tracks the live budget."
  def observe(headers, server \\ __MODULE__) do
    GenServer.cast(server, {:observe, parse_rate(headers)})
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
  def init([]) do
    # `limit: nil` until the first response calibrates us; until then requests are
    # let through (bounded by the caller's own concurrency) to read the headers.
    {:ok,
     %{used: 0, limit: nil, window: nil, reset_at: nil, refill_timer: nil, waiters: :queue.new()}}
  end

  @impl true
  def handle_call(:acquire, from, state) do
    state = refill(state)

    if available?(state) do
      {:reply, :ok, %{state | used: state.used + 1}}
    else
      {:noreply, schedule_refill(%{state | waiters: :queue.in(from, state.waiters)})}
    end
  end

  @impl true
  def handle_cast({:observe, nil}, state), do: {:noreply, state}

  def handle_cast({:observe, %{limit: limit, remaining: remaining, reset: reset}}, state) do
    {:noreply, release(observe_window(state, limit, remaining, reset))}
  end

  @impl true
  def handle_info(:refill, state) do
    {:noreply, release(refill(%{state | refill_timer: nil}))}
  end

  defp available?(%{limit: nil}), do: true
  defp available?(%{used: used, limit: limit}), do: used < limit

  # A later reset is a new window, so its remaining sets the baseline count; the
  # same window only ratchets the count up (the server's remaining lags ours); an
  # earlier reset is a stale, out-of-order response and is ignored.
  defp observe_window(state, limit, remaining, reset) do
    cond do
      state.window == nil or reset > state.window ->
        %{
          state
          | limit: limit,
            window: reset,
            reset_at: monotonic_deadline(reset),
            used: limit - remaining
        }

      reset == state.window ->
        %{state | limit: limit, used: max(state.used, limit - remaining)}

      true ->
        state
    end
  end

  # The window has elapsed: start the next one with a clean count. The next
  # response's reset identifies the new window and recalibrates from ground truth.
  defp refill(%{reset_at: reset_at} = state) when not is_nil(reset_at) do
    if System.monotonic_time(:millisecond) >= reset_at do
      %{state | used: 0, window: nil, reset_at: nil}
    else
      state
    end
  end

  defp refill(state), do: state

  defp release(state) do
    cond do
      not available?(state) ->
        state

      :queue.is_empty(state.waiters) ->
        state

      true ->
        {{:value, from}, waiters} = :queue.out(state.waiters)
        GenServer.reply(from, :ok)
        release(%{state | used: state.used + 1, waiters: waiters})
    end
  end

  defp schedule_refill(%{refill_timer: nil, reset_at: reset_at} = state)
       when not is_nil(reset_at) do
    delay = max(reset_at - System.monotonic_time(:millisecond) + 50, 0)
    %{state | refill_timer: Process.send_after(self(), :refill, delay)}
  end

  defp schedule_refill(state), do: state

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
