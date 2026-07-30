defmodule Bob.DockerHub.RateLimiterTest do
  use ExUnit.Case, async: true

  alias Bob.DockerHub.RateLimiter

  defp new_clock() do
    {:ok, clock} = Agent.start_link(fn -> 0 end)
    clock
  end

  defp advance(clock, ms), do: Agent.update(clock, &(&1 + ms))

  defp start_limiter(clock, opts \\ []) do
    opts = [name: nil, clock: fn -> Agent.get(clock, & &1) end, window_ms: 60_000] ++ opts
    {:ok, pid} = start_supervised({RateLimiter, opts})
    pid
  end

  defp headers(limit, remaining) do
    [
      {"x-ratelimit-limit", Integer.to_string(limit)},
      {"x-ratelimit-remaining", Integer.to_string(remaining)},
      {"x-ratelimit-reset", "1780736952"}
    ]
  end

  # observe/2 is a cast, so let it land before asserting on what follows.
  defp sync(limiter), do: :sys.get_state(limiter)

  defp take(limiter, headers) do
    assert RateLimiter.acquire(limiter) == :ok
    RateLimiter.observe(headers, limiter)
    sync(limiter)
  end

  defp blocks?(limiter) do
    task = Task.async(fn -> RateLimiter.acquire(limiter) end)
    result = Task.yield(task, 100)
    Task.shutdown(task)
    result == nil
  end

  describe "parse_rate/1" do
    test "extracts the limit and the remaining budget" do
      assert RateLimiter.parse_rate(headers(600, 396)) == %{limit: 600, remaining: 396}
    end

    test "matches header names case-insensitively" do
      raw = [{"X-RateLimit-Limit", "600"}, {"X-RateLimit-Remaining", "10"}]
      assert RateLimiter.parse_rate(raw) == %{limit: 600, remaining: 10}
    end

    test "keeps a negative remaining, which is how an overshoot is reported" do
      assert RateLimiter.parse_rate(headers(600, -534)) == %{limit: 600, remaining: -534}
    end

    test "returns nil when the rate-limit headers are absent" do
      assert RateLimiter.parse_rate([{"content-type", "application/json"}]) == nil
    end

    test "returns nil when a value is not an integer" do
      assert RateLimiter.parse_rate(headers(600, 600) ++ [{"x-ratelimit-remaining", "lots"}]) ==
               nil
    end
  end

  describe "the account budget" do
    test "admits while the budget lasts, then blocks" do
      clock = new_clock()
      limiter = start_limiter(clock)

      for remaining <- [4, 3, 2, 1, 0], do: take(limiter, headers(600, remaining))

      assert blocks?(limiter)
    end

    test "a budget spent by another node closes the gate on this one" do
      clock = new_clock()
      limiter = start_limiter(clock)

      take(limiter, headers(600, 600))
      take(limiter, headers(600, 1))

      assert RateLimiter.acquire(limiter) == :ok
      assert blocks?(limiter)
    end

    test "the budget is admitted against headroom for the requests in flight" do
      clock = new_clock()
      limiter = start_limiter(clock)

      take(limiter, headers(600, 3))

      # Three left on the reading, but each grant also has to clear the set the
      # server has not answered yet, so the last one is held back.
      for _ <- 1..2, do: assert(RateLimiter.acquire(limiter) == :ok)

      assert blocks?(limiter)
    end

    test "a spent budget reopens once the reading has aged out of the window" do
      clock = new_clock()
      limiter = start_limiter(clock)

      take(limiter, headers(600, 0))
      assert blocks?(limiter)

      advance(clock, 59_999)
      assert blocks?(limiter)

      advance(clock, 1)
      assert RateLimiter.acquire(limiter) == :ok
    end

    test "a recovered budget is seen as recovered" do
      clock = new_clock()
      limiter = start_limiter(clock)

      take(limiter, headers(600, 0))
      assert blocks?(limiter)

      advance(clock, 30_000)
      RateLimiter.observe(headers(600, 500), limiter)
      sync(limiter)

      assert RateLimiter.acquire(limiter) == :ok
    end
  end

  describe "the unmeasured path" do
    test "only one request goes until the budget has been measured" do
      clock = new_clock()
      limiter = start_limiter(clock)

      assert RateLimiter.acquire(limiter) == :ok
      assert blocks?(limiter)

      RateLimiter.observe(headers(5, 5), limiter)
      sync(limiter)

      assert RateLimiter.acquire(limiter) == :ok
    end

    test "responses without rate headers stay bounded by the trailing window" do
      clock = new_clock()
      limiter = start_limiter(clock)

      take(limiter, headers(2, 2))
      advance(clock, 60_000)

      # Every response now comes back without usable rate headers, so no reading
      # is ever established and `limit` plus the trailing sends are the only
      # thing holding this down.
      take(limiter, [])
      take(limiter, [])

      assert blocks?(limiter)
    end

    test "a reading older than the window is dropped and one request re-establishes it" do
      clock = new_clock()
      limiter = start_limiter(clock)

      take(limiter, headers(600, 600))
      advance(clock, 60_000)

      assert RateLimiter.acquire(limiter) == :ok
      assert blocks?(limiter)
    end

    test "a response without rate headers releases the slot without changing the budget" do
      clock = new_clock()
      limiter = start_limiter(clock)

      take(limiter, headers(600, 600))
      take(limiter, [])

      assert %{remaining: 600, in_flight: 0} = sync(limiter)
    end
  end

  describe "throttle/2" do
    test "a 429 without rate headers is read as a spent budget" do
      clock = new_clock()
      limiter = start_limiter(clock, park_ms: 5_000)

      take(limiter, headers(600, 600))

      RateLimiter.throttle([], limiter)
      sync(limiter)

      assert blocks?(limiter)

      # The park alone would have released a burst against the pre-429 reading.
      advance(clock, 5_000)
      assert blocks?(limiter)
    end

    test "a 429 carrying a budget holds the gate past the park" do
      clock = new_clock()
      limiter = start_limiter(clock, park_ms: 5_000)

      take(limiter, headers(600, 600))

      RateLimiter.throttle(headers(600, -534), limiter)
      sync(limiter)

      advance(clock, 5_000)
      assert blocks?(limiter)
    end
  end

  describe "slots" do
    test "a caller that dies without reporting does not keep its slot" do
      clock = new_clock()
      limiter = start_limiter(clock)

      take(limiter, headers(600, 3))

      task = Task.async(fn -> RateLimiter.acquire(limiter) end)
      assert Task.await(task) == :ok

      assert eventually(fn -> sync(limiter).in_flight == 0 end)
    end

    test "a slot held past the deadline is taken back" do
      clock = new_clock()
      limiter = start_limiter(clock, max_hold_ms: 120_000)

      take(limiter, headers(600, 2))

      # A caller that never reports would otherwise hold this for good, and the
      # gate is a singleton.
      holder = spawn(fn -> Process.sleep(:infinity) end)
      send(limiter, :wake)
      assert RateLimiter.acquire(limiter) == :ok
      assert sync(limiter).in_flight == 1

      advance(clock, 120_000)
      send(limiter, :wake)
      assert sync(limiter).in_flight == 0

      Process.exit(holder, :kill)
    end

    test "a waiter killed while queued is not handed a slot" do
      clock = new_clock()
      limiter = start_limiter(clock)

      take(limiter, headers(600, 0))

      task = Task.async(fn -> RateLimiter.acquire(limiter) end)
      assert Task.yield(task, 50) == nil
      Task.shutdown(task, :brutal_kill)

      before = :queue.len(sync(limiter).sends)

      # The budget recovers; the corpse must not be handed one of the slots.
      RateLimiter.observe(headers(600, 600), limiter)
      sync(limiter)

      assert :queue.len(sync(limiter).sends) == before
    end

    test "a caller arriving as the gate reopens does not jump the queue" do
      clock = new_clock()
      limiter = start_limiter(clock)

      take(limiter, headers(600, 0))

      parent = self()
      waiter = spawn(fn -> send(parent, {:admitted, RateLimiter.acquire(limiter)}) end)
      assert eventually(fn -> :queue.len(sync(limiter).waiters) == 1 end)

      advance(clock, 60_000)

      assert RateLimiter.acquire(limiter) == :ok
      assert_receive {:admitted, :ok}, 500

      Process.exit(waiter, :kill)
    end
  end

  defp eventually(fun, attempts \\ 50) do
    cond do
      fun.() -> true
      attempts == 0 -> false
      true -> Process.sleep(10) && eventually(fun, attempts - 1)
    end
  end
end
