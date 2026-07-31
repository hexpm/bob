defmodule Bob.DockerHub.RateLimiter do
  @moduledoc """
  Process-wide gate that paces Docker Hub API requests under the account's
  budget.

  Docker Hub meters a rolling window: `x-ratelimit-reset` is a moving estimate
  of when the oldest request ages out, recomputed on every response, not a
  boundary the count resets on. `x-ratelimit-remaining` is what the gate runs
  on, read against the requests still in flight, which the server has not
  counted yet. Because the budget is metered per account rather than per source
  IP, that reading is also what carries other nodes' spending: when one spends,
  the others see the budget fall and back off, with no shared state.

  A reading is a point measurement, but the budget it describes recovers
  continuously, so between responses the gate carries it forward: sends made
  since it was taken are subtracted, and sends that have since left the trailing
  window are added back, because the server stops counting them at the same
  moment. Without that the gate would have to wait out a whole window before it
  believed in any recovery at all.

  A reading older than the window is dropped, and until one exists the gate has
  no measure of the budget: one request goes on its own to take one, with the
  trailing count of its own sends held under `limit` so that a run of responses
  carrying no usable rate headers cannot send unchecked.

  Every granted caller is monitored so one that dies without reporting gives its
  slot back, and a slot held longer than `max_hold_ms` is taken back regardless.
  """

  use GenServer

  require Logger

  # Docker Hub meters a rolling minute. Our own sends are held for as long, and a
  # reading is treated as describing that same window.
  @window_ms 60_000

  # A floor on how long the gate stays shut after a 429. The reading taken from
  # it normally holds the gate well past this on its own.
  @park_ms 5_000

  # A slot is held from acquire until the caller reports. `receive_timeout`
  # applies per receive, so a response that trickles holds one for as long as it
  # keeps trickling, and this gate is a singleton: one wedged caller would stop
  # every Docker Hub request on the node.
  @max_hold_ms 120_000

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
       sent_total: 0,
       expired_total: 0,
       sent_at_reading: 0,
       expired_at_reading: 0,
       in_flight: 0,
       holders: %{},
       parked_until: nil,
       waiters: :queue.new(),
       timer: nil,
       window_ms: Keyword.get(opts, :window_ms, @window_ms),
       park_ms: Keyword.get(opts, :park_ms, @park_ms),
       max_hold_ms: Keyword.get(opts, :max_hold_ms, @max_hold_ms),
       clock: Keyword.get(opts, :clock, &__MODULE__.monotonic_ms/0)
     }}
  end

  @doc false
  def monotonic_ms(), do: System.monotonic_time(:millisecond)

  # Queued behind any existing waiters rather than taking a slot that just
  # opened, so a caller that arrives as the gate reopens cannot jump the queue.
  @impl true
  def handle_call(:acquire, from, state) do
    state = expire(state)

    if :queue.is_empty(state.waiters) and available?(state) do
      {:reply, :ok, grant(state, elem(from, 0))}
    else
      {:noreply, schedule(admit(%{state | waiters: :queue.in(from, state.waiters)}))}
    end
  end

  @impl true
  def handle_cast({:observe, rate, pid}, state) do
    state = state |> release_slot(pid) |> apply_rate(rate) |> expire()
    {:noreply, schedule(admit(state))}
  end

  # A 429 means the budget is spent whatever the response carried, so one
  # without usable headers is read as zero. Leaving the previous reading in
  # place would release a burst as soon as the park cleared.
  def handle_cast({:throttle, rate, pid}, state) do
    rate = rate || %{limit: state.limit || 1, remaining: 0}
    state = state |> release_slot(pid) |> apply_rate(rate) |> expire()
    state = %{state | parked_until: state.clock.() + state.park_ms}

    Logger.warning("DockerHub rate limited, holding until the window frees budget")

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
        %{^pid => {_ref, holds}} ->
          %{
            state
            | holders: Map.delete(state.holders, pid),
              in_flight: state.in_flight - length(holds)
          }

        _ ->
          state
      end

    {:noreply, schedule(admit(expire(state)))}
  end

  defp available?(%{parked_until: parked}) when not is_nil(parked), do: false

  # No reading to run on: one request goes on its own to take one, still bounded
  # by the trailing count so a run of header-less responses cannot send
  # unchecked.
  defp available?(%{remaining: nil} = state) do
    state.in_flight == 0 and within_window?(state)
  end

  defp available?(state), do: credited_remaining(state) > state.in_flight

  # Admitted against headroom the size of the in-flight set. Our sends are
  # credited back when they leave our window, but the server counted them when
  # it answered and drops them that much later, so crediting runs slightly ahead
  # of the truth and the headroom absorbs it.
  defp credited_remaining(state) do
    state.remaining - (state.sent_total - state.sent_at_reading) +
      (state.expired_total - state.expired_at_reading)
  end

  defp within_window?(%{limit: nil}), do: true
  defp within_window?(state), do: :queue.len(state.sends) < state.limit

  defp grant(state, pid) do
    now = state.clock.()

    holders =
      case state.holders do
        %{^pid => {ref, holds}} -> Map.put(state.holders, pid, {ref, [now | holds]})
        _ -> Map.put(state.holders, pid, {Process.monitor(pid), [now]})
      end

    %{
      state
      | sends: :queue.in(now, state.sends),
        sent_total: state.sent_total + 1,
        in_flight: state.in_flight + 1,
        holders: holders
    }
  end

  defp release_slot(state, pid) do
    case state.holders do
      %{^pid => {ref, [_only]}} ->
        Process.demonitor(ref, [:flush])
        %{state | holders: Map.delete(state.holders, pid), in_flight: state.in_flight - 1}

      %{^pid => {ref, [_oldest | rest]}} ->
        %{
          state
          | holders: Map.put(state.holders, pid, {ref, rest}),
            in_flight: state.in_flight - 1
        }

      _ ->
        state
    end
  end

  # The newest reading wins, so a budget that has recovered is seen as recovered.
  defp apply_rate(state, nil), do: state

  defp apply_rate(state, %{limit: limit, remaining: remaining}) do
    %{
      state
      | limit: limit,
        remaining: remaining,
        measured_at: state.clock.(),
        sent_at_reading: state.sent_total,
        expired_at_reading: state.expired_total
    }
  end

  # Ages out the sends that have left the window, the park, a reading taken in a
  # window that has since rolled, and any slot held past the deadline.
  defp expire(state) do
    now = state.clock.()
    cutoff = now - state.window_ms
    stale? = state.measured_at != nil and state.measured_at <= cutoff

    {sends, expired} = drop_before(state.sends, cutoff, 0)

    %{
      state
      | sends: sends,
        expired_total: state.expired_total + expired,
        parked_until: if(parked?(state.parked_until, now), do: state.parked_until),
        remaining: if(stale?, do: nil, else: state.remaining),
        measured_at: if(stale?, do: nil, else: state.measured_at)
    }
    |> reap_holders(now)
  end

  defp parked?(nil, _now), do: false
  defp parked?(parked_until, now), do: now < parked_until

  defp reap_holders(state, now) do
    deadline = now - state.max_hold_ms

    Enum.reduce(state.holders, state, fn {pid, {ref, holds}}, acc ->
      case Enum.reject(holds, &(&1 <= deadline)) do
        ^holds ->
          acc

        kept ->
          Logger.warning(
            "DockerHub rate limiter reclaiming #{length(holds) - length(kept)} slot(s) " <>
              "held past #{div(state.max_hold_ms, 1000)}s by #{inspect(pid)}"
          )

          acc = %{acc | in_flight: acc.in_flight - (length(holds) - length(kept))}

          if kept == [] do
            Process.demonitor(ref, [:flush])
            %{acc | holders: Map.delete(acc.holders, pid)}
          else
            %{acc | holders: Map.put(acc.holders, pid, {ref, kept})}
          end
      end
    end)
  end

  defp drop_before(sends, cutoff, dropped) do
    case :queue.peek(sends) do
      {:value, at} when at <= cutoff -> drop_before(:queue.drop(sends), cutoff, dropped + 1)
      _ -> {sends, dropped}
    end
  end

  # A waiter killed while queued would otherwise be handed a slot and counted
  # against the window for nothing.
  defp admit(state) do
    cond do
      :queue.is_empty(state.waiters) ->
        state

      not available?(state) ->
        state

      true ->
        {{:value, from}, waiters} = :queue.out(state.waiters)
        pid = elem(from, 0)
        state = %{state | waiters: waiters}

        if Process.alive?(pid) do
          GenServer.reply(from, :ok)
          admit(grant(state, pid))
        else
          admit(state)
        end
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

    oldest_hold =
      state.holders
      |> Enum.flat_map(fn {_pid, {_ref, holds}} -> holds end)
      |> Enum.min(fn -> nil end)

    [
      state.parked_until,
      oldest_send,
      state.measured_at && state.measured_at + state.window_ms,
      oldest_hold && oldest_hold + state.max_hold_ms
    ]
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
