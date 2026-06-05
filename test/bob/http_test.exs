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
end
