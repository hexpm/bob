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

  describe "track_request/3" do
    setup do
      handler = {__MODULE__, make_ref()}

      :telemetry.attach(
        handler,
        [:bob, :http, :request, :stop],
        &__MODULE__.request_event/4,
        self()
      )

      on_exit(fn -> :telemetry.detach(handler) end)
      :ok
    end

    test "records one success after retries without exposing request or response contents" do
      success = {:ok, 200, [{"set-cookie", "private"}], "private response"}
      fun = counter([{:error, :closed}, {:ok, 503, [], ""}, success])
      url = "https://user:password@api.github.com/private?token=secret"

      assert HTTP.track_request(:get, url, fn ->
               HTTP.retry("test", fun, sleep: fn _ -> :ok end)
             end) == success

      assert_receive {:final_request, metadata}
      assert metadata == %{host: "api.github.com", method: "GET", status: 200}
      refute_receive {:final_request, _}
    end

    for {failure, status} <- [
          {{:ok, 503, [], ""}, 503},
          {{:error, :timeout}, "error"},
          {{:ok, 429, [], ""}, 429}
        ] do
      test "records one final failure after exhausting #{inspect(failure)}" do
        failure = unquote(Macro.escape(failure))
        fun = counter(List.duplicate(failure, 10))

        assert HTTP.track_request(:post, "https://api.fastly.com/service/test/purge", fn ->
                 HTTP.retry("test", fun, sleep: fn _ -> :ok end)
               end) == failure

        status = unquote(status)

        assert_receive {:final_request, metadata}
        assert metadata == %{host: "api.fastly.com", method: "POST", status: status}
        refute_receive {:final_request, _}
      end
    end

    test "records client errors as their final status" do
      result = {:ok, 401, [], ""}
      fun = counter([result])

      assert HTTP.track_request("POST", "https://bob.hex.pm/api/queue/start", fn ->
               HTTP.retry("test", fun)
             end) == result

      assert_receive {:final_request, %{host: "bob.hex.pm", method: "POST", status: 401}}
      refute_receive {:final_request, _}
    end
  end

  def request_event(_event, _measurements, metadata, pid) do
    if self() == pid, do: send(pid, {:final_request, metadata})
  end

  test "backoff grows exponentially but is capped" do
    assert HTTP.backoff(100, 0) == 100
    assert HTTP.backoff(100, 3) == 2_700
    assert HTTP.backoff(100, 20) == 30_000
    assert HTTP.backoff(10_000, 20) == 30_000
  end
end
