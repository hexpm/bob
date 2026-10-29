defmodule Bob.PromEx.Plugins.OutboundHttpTest do
  # The request tests collect every Finch request the VM makes, so they run
  # apart from the async tests that make requests.
  use ExUnit.Case, async: false

  alias Bob.PromEx.Plugins.OutboundHttp

  test "falls back when the result is not a response" do
    request = Finch.build(:get, "https://s3.amazonaws.com/")

    assert OutboundHttp.request_tags(%{request: request, result: nil}).status == "unknown"
  end

  test "attaches to attempt and final outcome events" do
    events =
      [otp_app: :bob]
      |> OutboundHttp.event_metrics()
      |> List.wrap()
      |> Enum.flat_map(& &1.metrics)
      |> Enum.map(& &1.event_name)
      |> Enum.uniq()

    assert [:bob, :http, :request, :stop] in events
    assert [:finch, :request, :stop] in events
    assert [:finch, :request, :exception] in events
    assert [:finch, :queue, :stop] in events
    assert [:finch, :connect, :stop] in events
  end

  describe "a request through Finch" do
    setup do
      # Answers with the status in the first path segment, 204 without one.
      plug = fn conn, _opts ->
        status = conn.path_info |> List.first("204") |> String.to_integer()
        Plug.Conn.send_resp(conn, status, "")
      end

      server =
        start_supervised!({Bandit, plug: plug, ip: :loopback, port: 0, startup_log: false},
          id: :server
        )

      {:ok, {_ip, port}} = ThousandIsland.listener_info(server)

      finch = :"#{__MODULE__}.Finch"
      start_supervised!({Finch, name: finch})

      name = :"#{__MODULE__}.Metrics"

      metrics =
        [otp_app: :bob]
        |> OutboundHttp.event_metrics()
        |> List.wrap()
        |> Enum.flat_map(& &1.metrics)

      start_supervised!(PromEx.Storage.Core.child_spec(name, metrics))

      %{url: "http://127.0.0.1:#{port}/", port: port, finch: finch, metrics: name}
    end

    test "tags the request, the pool wait and the connect by host", context do
      request = Finch.build(:get, context.url)
      assert {:ok, %Finch.Response{status: 204}} = Finch.request(request, context.finch)

      scrape = PromEx.Storage.Core.scrape(context.metrics)

      assert scrape =~
               ~s(bob_prom_ex_outbound_http_request_total{host="127.0.0.1",method="GET",status="204"} 1\n)

      assert scrape =~
               ~s(bob_prom_ex_outbound_http_request_duration_milliseconds_count{host="127.0.0.1",method="GET",status="204"} 1\n)

      assert scrape =~
               ~s(bob_prom_ex_outbound_http_queue_duration_milliseconds_count{host="127.0.0.1"} 1\n)

      assert scrape =~
               ~s(bob_prom_ex_outbound_http_connect_duration_milliseconds_count{host="127.0.0.1"} 1\n)
    end

    test "tags a refused connection by host", context do
      stop_supervised!(:server)
      request = Finch.build(:get, context.url)

      assert {:error, %Finch.TransportError{reason: :econnrefused}} =
               Finch.request(request, context.finch)

      scrape = PromEx.Storage.Core.scrape(context.metrics)

      assert scrape =~
               ~s(bob_prom_ex_outbound_http_request_total{host="127.0.0.1",method="GET",status="Finch.TransportError"} 1\n)

      assert scrape =~
               ~s(bob_prom_ex_outbound_http_connect_duration_milliseconds_count{host="127.0.0.1"} 1\n)
    end

    test "tags an S3 request sent through Req by its response status", context do
      operation = ExAws.S3.list_objects("403")

      assert {:error, {:http_error, 403, _response}} =
               ExAws.request(operation, s3_config(context))

      scrape = PromEx.Storage.Core.scrape(context.metrics)

      assert scrape =~
               ~s(bob_prom_ex_outbound_http_request_total{host="127.0.0.1",method="GET",status="403"} 1\n)
    end

    test "tags an S3 request sent through Req that failed by its error", context do
      stop_supervised!(:server)
      operation = ExAws.S3.list_objects("bucket")

      assert {:error, _reason} = ExAws.request(operation, s3_config(context))

      scrape = PromEx.Storage.Core.scrape(context.metrics)

      assert scrape =~
               ~s(bob_prom_ex_outbound_http_request_total{host="127.0.0.1",method="GET",status="Finch.TransportError"} 1\n)
    end

    test "tags a request that raised by host, method and kind", context do
      request = Finch.build(:post, context.url)

      assert_raise RuntimeError, "reducer failed", fn ->
        Finch.stream(request, context.finch, nil, fn _chunk, _acc -> raise "reducer failed" end)
      end

      scrape = PromEx.Storage.Core.scrape(context.metrics)

      assert scrape =~
               ~s(bob_prom_ex_outbound_http_request_exception_total{host="127.0.0.1",kind="error",method="POST"} 1\n)
    end
  end

  # Production sends ExAws through ExAws.Request.Req, and the tests through a
  # fake client.
  defp s3_config(context) do
    [
      http_client: ExAws.Request.Req,
      scheme: "http://",
      host: "127.0.0.1",
      port: context.port,
      retries: [max_attempts: 1]
    ]
  end
end
