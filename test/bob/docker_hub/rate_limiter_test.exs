defmodule Bob.DockerHub.RateLimiterTest do
  use ExUnit.Case, async: true

  alias Bob.DockerHub.RateLimiter

  defp start_limiter(opts) do
    {:ok, pid} = start_supervised({RateLimiter, [name: nil] ++ opts})
    pid
  end

  defp headers(limit, remaining, reset) do
    [
      {"x-ratelimit-limit", Integer.to_string(limit)},
      {"x-ratelimit-remaining", Integer.to_string(remaining)},
      {"x-ratelimit-reset", Integer.to_string(reset)}
    ]
  end

  defp blocks?(limiter) do
    task = Task.async(fn -> RateLimiter.acquire(limiter) end)
    result = Task.yield(task, 100)
    Task.shutdown(task)
    result == nil
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
    test "bursts the whole window immediately, then blocks" do
      limiter = start_limiter(offset_ms: 0)
      reset = System.os_time(:second) + 3600

      RateLimiter.observe(headers(5, 5, reset), limiter)

      for _ <- 1..5, do: assert(RateLimiter.acquire(limiter) == :ok)
      assert blocks?(limiter)
    end

    test "allows a single calibration probe, then blocks until a response anchors the window" do
      limiter = start_limiter(offset_ms: 0)
      assert RateLimiter.acquire(limiter) == :ok
      assert blocks?(limiter)
    end

    test "seeds the count from the server's reported usage" do
      limiter = start_limiter(offset_ms: 0)
      reset = System.os_time(:second) + 3600

      # remaining 2 of 5 means 3 are already spent, so only 2 more are allowed.
      RateLimiter.observe(headers(5, 2, reset), limiter)

      assert RateLimiter.acquire(limiter) == :ok
      assert RateLimiter.acquire(limiter) == :ok
      assert blocks?(limiter)
    end

    test "ratchets the count up when external usage outruns ours" do
      limiter = start_limiter(offset_ms: 0)
      reset = System.os_time(:second) + 3600

      RateLimiter.observe(headers(5, 5, reset), limiter)
      assert RateLimiter.acquire(limiter) == :ok

      # Same window now reports only 1 left (something else spent budget): the
      # count jumps to 4, so just one more grant remains.
      RateLimiter.observe(headers(5, 1, reset), limiter)
      assert RateLimiter.acquire(limiter) == :ok
      assert blocks?(limiter)
    end

    test "rolls to a fresh window once the reset has passed" do
      limiter = start_limiter(offset_ms: 0)

      # Window fully spent, but its reset is already in the past.
      RateLimiter.observe(headers(5, 0, System.os_time(:second) - 1), limiter)

      assert RateLimiter.acquire(limiter) == :ok
    end

    test "the offset holds the window past the server's stated reset" do
      limiter = start_limiter(offset_ms: 60_000)

      # Server says the window resets now, but the offset keeps us waiting.
      RateLimiter.observe(headers(5, 0, System.os_time(:second)), limiter)

      assert blocks?(limiter)
    end

    test "releases a blocked caller when the window rolls" do
      limiter = start_limiter(offset_ms: 100)

      RateLimiter.observe(headers(5, 0, System.os_time(:second)), limiter)

      task = Task.async(fn -> RateLimiter.acquire(limiter) end)
      assert Task.yield(task, 30) == nil
      assert Task.await(task, 2000) == :ok
    end

    test "reclaims the probe slot when the probe dies without anchoring the window" do
      limiter = start_limiter(offset_ms: 0)

      # A caller takes the single calibration probe, then exits without ever
      # reporting server headers (a non-2xx/429 response or a crash).
      {pid, ref} = spawn_monitor(fn -> RateLimiter.acquire(limiter) end)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000

      # Without reclaiming the dead probe's slot, the gate would stay shut
      # forever: window unanchored, count stuck at one, nothing left to roll it.
      assert RateLimiter.acquire(limiter) == :ok
    end

    test "keeps the probe's slot when it anchored the window before exiting" do
      limiter = start_limiter(offset_ms: 0)
      reset = System.os_time(:second) + 3600

      {pid, ref} =
        spawn_monitor(fn ->
          RateLimiter.acquire(limiter)
          RateLimiter.observe(headers(2, 1, reset), limiter)
        end)

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000

      # limit 2 with one already spent by the probe: exactly one grant remains.
      assert RateLimiter.acquire(limiter) == :ok
      assert blocks?(limiter)
    end
  end

  describe "throttle/2" do
    test "a 429 with rate headers holds the gate shut until the window resets" do
      limiter = start_limiter(offset_ms: 0)
      reset = System.os_time(:second) + 3600

      RateLimiter.throttle(headers(600, 0, reset), limiter)

      assert blocks?(limiter)
    end

    test "a 429 without rate headers holds the gate shut on the fallback window" do
      limiter = start_limiter(offset_ms: 0)

      RateLimiter.throttle([{"retry-after", "30"}], limiter)

      assert blocks?(limiter)
    end
  end
end
