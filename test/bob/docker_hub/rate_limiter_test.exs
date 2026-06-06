defmodule Bob.DockerHub.RateLimiterTest do
  use ExUnit.Case, async: true

  alias Bob.DockerHub.RateLimiter

  defp start_limiter do
    {:ok, pid} = start_supervised({RateLimiter, name: nil})
    pid
  end

  defp headers(limit, remaining, reset) do
    [
      {"x-ratelimit-limit", Integer.to_string(limit)},
      {"x-ratelimit-remaining", Integer.to_string(remaining)},
      {"x-ratelimit-reset", Integer.to_string(reset)}
    ]
  end

  describe "parse_rate/1" do
    test "extracts the limit, remaining budget, and reset time" do
      assert RateLimiter.parse_rate(headers(600, 396, 1_780_736_952)) ==
               %{limit: 600, remaining: 396, reset: 1_780_736_952}
    end

    test "matches header names case-insensitively" do
      raw = [
        {"X-RateLimit-Limit", "600"},
        {"X-RateLimit-Remaining", "10"},
        {"X-RateLimit-Reset", "1780736952"}
      ]

      assert RateLimiter.parse_rate(raw) == %{limit: 600, remaining: 10, reset: 1_780_736_952}
    end

    test "returns nil when the rate-limit headers are absent" do
      assert RateLimiter.parse_rate([{"content-type", "application/json"}]) == nil
    end

    test "returns nil when a value is not an integer" do
      assert RateLimiter.parse_rate(headers(600, 600, 0) ++ [{"x-ratelimit-remaining", "lots"}]) ==
               nil
    end
  end

  describe "acquire/1 + observe/2" do
    test "grants exactly the reported remaining, then blocks until the window resets" do
      limiter = start_limiter()
      reset = System.os_time(:second) + 3600

      # remaining = 2 with no reserve means exactly two more requests are allowed.
      RateLimiter.observe(headers(600, 2, reset), limiter)

      assert RateLimiter.acquire(limiter) == :ok
      assert RateLimiter.acquire(limiter) == :ok

      # Budget exhausted and the window is an hour out: the next acquire blocks.
      task = Task.async(fn -> RateLimiter.acquire(limiter) end)
      assert Task.yield(task, 100) == nil
      Task.shutdown(task)
    end

    test "refills the budget once the reset time has passed" do
      limiter = start_limiter()

      # Window fully spent (remaining 0), but its reset is already in the past.
      RateLimiter.observe(headers(600, 0, System.os_time(:second) - 1), limiter)

      # The elapsed window is refilled rather than blocking.
      assert RateLimiter.acquire(limiter) == :ok
    end

    test "ratchets the count up within a window and ignores stale older windows" do
      limiter = start_limiter()
      reset = System.os_time(:second) + 3600

      RateLimiter.observe(headers(600, 5, reset), limiter)

      # An out-of-order response from the same window reporting more headroom must
      # not raise the budget back up.
      RateLimiter.observe(headers(600, 500, reset), limiter)

      for _ <- 1..5, do: assert(RateLimiter.acquire(limiter) == :ok)

      task = Task.async(fn -> RateLimiter.acquire(limiter) end)
      assert Task.yield(task, 100) == nil
      Task.shutdown(task)
    end

    test "releases a blocked caller when the next window is observed" do
      limiter = start_limiter()
      reset = System.os_time(:second) + 3600

      RateLimiter.observe(headers(600, 0, reset), limiter)

      # Budget is 0 in this window, so this acquire parks.
      task = Task.async(fn -> RateLimiter.acquire(limiter) end)
      assert Task.yield(task, 50) == nil

      # A response from a later window (higher reset) wakes the parked caller.
      RateLimiter.observe(headers(600, 600, reset + 60), limiter)
      assert Task.await(task, 1000) == :ok
    end
  end
end
