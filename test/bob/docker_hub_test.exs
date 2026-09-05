defmodule Bob.DockerHubTest do
  use ExUnit.Case, async: true

  alias Bob.DockerHub

  @built_at ~U[2025-01-02 03:04:05.123456Z]
  @image_pushed_at ~U[2025-02-03 04:05:06.000000Z]

  describe "parse/1" do
    test "returns tag, archs and built_at" do
      assert DockerHub.parse(
               tag_payload(%{
                 "last_updated" => "2025-01-02T03:04:05.123456Z",
                 "images" => [
                   image("amd64", "sha256:amd64", "2025-02-03T04:05:06Z"),
                   image("arm64", "sha256:arm64", "2025-02-03T04:05:06Z")
                 ]
               })
             ) == {"27.0", ["amd64", "arm64"], @built_at}
    end

    test "falls back to image last_pushed when the tag timestamp is absent" do
      assert DockerHub.parse(
               tag_payload(%{
                 "images" => [
                   image("amd64", "sha256:amd64", "2025-01-03T04:05:06Z"),
                   image("arm64", "sha256:arm64", "2025-02-03T04:05:06Z")
                 ]
               })
             ) == {"27.0", ["amd64", "arm64"], @image_pushed_at}
    end

    test "rejects images without a digest" do
      assert DockerHub.parse(
               tag_payload(%{
                 "last_updated" => "2025-01-02T03:04:05.123456Z",
                 "images" => [image("amd64", nil, "2025-02-03T04:05:06Z")]
               })
             ) == nil
    end

    test "rejects tags without a Docker Hub timestamp" do
      assert DockerHub.parse(
               tag_payload(%{
                 "images" => [%{"architecture" => "amd64", "digest" => "sha256:amd64"}]
               })
             ) == nil
    end
  end

  describe "requests" do
    setup do
      handler = {__MODULE__, make_ref()}

      :telemetry.attach(
        handler,
        [:bob, :docker_hub, :request, :stop],
        &__MODULE__.request_event/4,
        self()
      )

      on_exit(fn -> :telemetry.detach(handler) end)
      :ok
    end

    test "paces every attempt and counts a recovered request once" do
      metric =
        [otp_app: :bob]
        |> Bob.PromEx.Plugins.OutboundHttp.event_metrics()
        |> Map.fetch!(:metrics)
        |> Enum.find(&(&1.name == [:bob, :docker_hub, :request, :total]))

      start_supervised!(
        {TelemetryMetricsPrometheus.Core,
         name: __MODULE__.Metrics, metrics: [metric], start_async: false}
      )

      body =
        JSON.encode!(
          tag_payload(%{
            "last_updated" => "2025-01-02T03:04:05.123456Z",
            "images" => [image("amd64", "sha256:amd64", "2025-02-03T04:05:06Z")]
          })
        )

      success = {:ok, 200, [], body}
      opts = request_opts([{:error, :closed}, {:ok, 503, [], ""}, success])

      assert DockerHub.fetch_tag("hexpm/erlang", "27.0", opts) ==
               {:ok, {"27.0", ["amd64"], @built_at}}

      for _ <- 1..3 do
        assert_receive {:attempt, :get,
                        "https://hub.docker.com/v2/repositories/hexpm/erlang/tags/27.0", "",
                        [recv_timeout: 20_000]}
      end

      assert :sys.get_state(opts[:rate_limiter]).sent_total == 3
      assert_receive {:request_result, %{method: :get, result: ^success}}
      refute_receive {:request_result, _}
      refute_receive {:attempt, _, _, _, _}

      metrics = TelemetryMetricsPrometheus.Core.scrape(__MODULE__.Metrics)
      assert metrics =~ ~s(bob_docker_hub_request_total{method="GET",status="200"} 1)
      refute metrics =~ ~s(status="503")
      refute metrics =~ ~s(status="error")
    end

    for failure <- [{:ok, 503, [], ""}, {:error, :timeout}] do
      test "returns unreadable and records one result after exhausting #{inspect(failure)}" do
        failure = unquote(Macro.escape(failure))
        opts = request_opts(List.duplicate(failure, 10))

        assert DockerHub.fetch_tag("hexpm/erlang", "27.0", opts) == :unreadable
        for _ <- 1..10, do: assert_receive({:attempt, :get, _, _, _})
        assert_receive {:request_result, %{method: :get, result: ^failure}}
        refute_receive {:request_result, _}
        refute_receive {:attempt, _, _, _, _}
      end
    end

    test "counts a rate-limited request once after it recovers" do
      success = {:ok, 204, [], ""}
      opts = request_opts([{:ok, 429, [], ""}, success])

      assert DockerHub.paced_request(:delete, "https://hub.docker.com/tag", opts) == success
      assert_receive {:request_result, %{method: :delete, result: ^success}}
      assert :sys.get_state(opts[:rate_limiter]).sent_total == 2
      refute_receive {:request_result, _}
    end

    test "stops after exhausting rate-limit retries" do
      failure = {:ok, 429, [], ""}
      opts = request_opts(List.duplicate(failure, 6))

      assert DockerHub.fetch_tag("hexpm/erlang", "27.0", opts) == :unreadable
      assert :sys.get_state(opts[:rate_limiter]).sent_total == 6
      assert_receive {:request_result, %{result: ^failure}}
      refute_receive {:request_result, _}
    end

    test "a missing tag remains distinct from a failed request" do
      opts = request_opts([{:ok, 404, [], ""}])
      assert DockerHub.fetch_tag("hexpm/erlang", "27.0", opts) == :not_found
      assert_receive {:request_result, %{result: {:ok, 404, [], ""}}}
    end

    test "does not retry an authentication failure or treat it as a missing tag" do
      opts = request_opts([{:ok, 401, [], ""}])
      assert DockerHub.fetch_tag("hexpm/erlang", "27.0", opts) == :unreadable
      assert :sys.get_state(opts[:rate_limiter]).sent_total == 1
      assert_receive {:request_result, %{result: {:ok, 401, [], ""}}}
    end

    for body <- ["invalid json", "null", "[]", "{}"] do
      test "returns unreadable for an unusable response: #{body}" do
        opts = request_opts([{:ok, 200, [], unquote(body)}])
        assert DockerHub.fetch_tag("hexpm/erlang", "27.0", opts) == :unreadable
      end
    end

    test "leaves an existing manifest alone after lookup retries are exhausted" do
      opts = request_opts(List.duplicate({:ok, 503, [], ""}, 10))
      fetch = fn repo, tag -> DockerHub.fetch_tag(repo, tag, opts) end

      refute Bob.Job.DockerManifest.publish?("erlang", "27.0", [{"amd64", @built_at}], fetch)
    end

    test "does not publish a partial manifest when a source lookup fails" do
      opts = request_opts(List.duplicate({:error, :closed}, 10))
      fetch = fn repo, tag -> DockerHub.fetch_tag(repo, tag, opts) end

      assert Bob.Job.DockerManifest.get_archs("erlang", "27.0", fetch) == {:unreadable, "amd64"}
      assert :sys.get_state(opts[:rate_limiter]).sent_total == 10
    end
  end

  def request_event(_event, _measurements, metadata, pid) do
    if self() == pid, do: send(pid, {:request_result, metadata})
  end

  defp request_opts(responses) do
    responses = start_supervised!({Agent, fn -> responses end})
    limiter = start_supervised!({DockerHub.RateLimiter, name: nil, window_ms: 0, park_ms: 0})
    pid = self()

    request = fn method, url, _headers, body, opts ->
      send(pid, {:attempt, method, url, body, opts})
      Agent.get_and_update(responses, fn [response | rest] -> {response, rest} end)
    end

    [request: request, rate_limiter: limiter, sleep: fn _duration -> :ok end]
  end

  defp tag_payload(attrs) do
    Map.merge(
      %{
        "name" => "27.0",
        "images" => []
      },
      attrs
    )
  end

  defp image(arch, digest, last_pushed) do
    %{
      "architecture" => arch,
      "digest" => digest,
      "last_pushed" => last_pushed
    }
  end
end
