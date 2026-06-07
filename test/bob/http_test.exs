defmodule Bob.HTTPTest do
  use ExUnit.Case

  alias Bob.HTTP

  defp counter(responses) do
    {:ok, agent} = Agent.start_link(fn -> responses end)

    fn ->
      Agent.get_and_update(agent, fn [response | rest] -> {response, rest} end)
    end
  end

  test "returns successful responses without retrying" do
    fun = counter([{:ok, 200, [], "body"}])
    assert HTTP.retry("test", fun) == {:ok, 200, [], "body"}
  end

  test "retries on server errors until success" do
    fun = counter([{:ok, 502, [], ""}, {:ok, 500, [], ""}, {:ok, 200, [], "ok"}])
    assert HTTP.retry("test", fun) == {:ok, 200, [], "ok"}
  end

  test "retries on transport errors until success" do
    fun = counter([{:error, :closed}, {:ok, 200, [], "ok"}])
    assert HTTP.retry("test", fun) == {:ok, 200, [], "ok"}
  end

  test "does not retry client errors" do
    fun = counter([{:ok, 404, [], ""}])
    assert HTTP.retry("test", fun) == {:ok, 404, [], ""}
  end

  test "returns a 429 without retrying when retry_rate_limit? is false" do
    fun = counter([{:ok, 429, [{"x-ratelimit-remaining", "0"}], ""}])

    assert HTTP.retry("test", fun, retry_rate_limit?: false) ==
             {:ok, 429, [{"x-ratelimit-remaining", "0"}], ""}
  end

  test "backoff grows exponentially but is capped" do
    assert HTTP.backoff(100, 0) == 100
    assert HTTP.backoff(100, 3) == 2_700
    assert HTTP.backoff(100, 20) == 30_000
    assert HTTP.backoff(10_000, 20) == 30_000
  end
end
