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

  describe "the trailing window" do
    test "admits up to the limit, then blocks" do
      clock = new_clock()
      limiter = start_limiter(clock)

      for _ <- 1..5, do: take(limiter, headers(5, 5))

      assert blocks?(limiter)
    end

    test "a send frees its slot only once it has left the window" do
      clock = new_clock()
      limiter = start_limiter(clock)

      take(limiter, headers(5, 5))
      advance(clock, 1_000)
      for _ <- 1..4, do: take(limiter, headers(5, 5))

      assert blocks?(limiter)

      advance(clock, 58_999)
      assert blocks?(limiter)

      advance(clock, 1)
      assert RateLimiter.acquire(limiter) == :ok
    end

    test "a slot reopens per send that ages out, not a whole budget at once" do
      clock = new_clock()
      limiter = start_limiter(clock)

      take(limiter, headers(5, 5))
      advance(clock, 55_000)
      for _ <- 1..4, do: take(limiter, headers(5, 5))

      advance(clock, 5_000)

      assert RateLimiter.acquire(limiter) == :ok
      assert blocks?(limiter)
    end
  end

  describe "the account budget" do
    test "a remaining spent by another node closes the gate while our own window has room" do
      clock = new_clock()
      limiter = start_limiter(clock)

      take(limiter, headers(600, 600))
      take(limiter, headers(600, 1))

      assert RateLimiter.acquire(limiter) == :ok
      assert blocks?(limiter)
    end

    test "remaining is read against the requests still in flight" do
      clock = new_clock()
      limiter = start_limiter(clock)

      take(limiter, headers(600, 3))

      # The server has not counted these yet, so they come off the reading.
      for _ <- 1..3, do: assert(RateLimiter.acquire(limiter) == :ok)

      assert blocks?(limiter)
    end

    test "only one request goes until the budget has been measured" do
      clock = new_clock()
      limiter = start_limiter(clock)

      assert RateLimiter.acquire(limiter) == :ok
      assert blocks?(limiter)

      RateLimiter.observe(headers(5, 5), limiter)
      sync(limiter)

      assert RateLimiter.acquire(limiter) == :ok
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
    test "a 429 holds the gate shut until the park elapses" do
      clock = new_clock()
      limiter = start_limiter(clock, park_ms: 5_000)

      take(limiter, headers(600, 600))

      RateLimiter.throttle([], limiter)
      sync(limiter)

      assert blocks?(limiter)

      advance(clock, 5_000)
      assert RateLimiter.acquire(limiter) == :ok
    end

    test "a 429 carrying a negative remaining keeps the gate shut past the park" do
      clock = new_clock()
      limiter = start_limiter(clock, park_ms: 5_000)

      take(limiter, headers(600, 600))

      RateLimiter.throttle(headers(600, -534), limiter)
      sync(limiter)

      advance(clock, 5_000)
      assert blocks?(limiter)
    end
  end

  describe "callers that die" do
    test "a caller that dies without reporting does not keep its slot" do
      clock = new_clock()
      limiter = start_limiter(clock)

      take(limiter, headers(3, 3))

      task = Task.async(fn -> RateLimiter.acquire(limiter) end)
      assert Task.await(task) == :ok

      assert eventually(fn -> sync(limiter).in_flight == 0 end)
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
