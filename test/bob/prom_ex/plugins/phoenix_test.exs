defmodule Bob.PromEx.Plugins.PhoenixTest do
  # The request test collects every Phoenix request the endpoint serves, so it
  # runs apart from the async tests that make requests.
  use BobWeb.ConnCase, async: false

  alias Bob.PromEx.Plugins.Phoenix, as: Plugin
  alias PromEx.Plugins.Phoenix, as: Upstream

  @opts [otp_app: :bob, router: BobWeb.Router, endpoint: BobWeb.Endpoint]

  @relabelled [
    [:bob, :prom_ex, :phoenix, :http, :request, :duration, :milliseconds],
    [:bob, :prom_ex, :phoenix, :http, :response, :size, :bytes],
    [:bob, :prom_ex, :phoenix, :http, :requests, :total]
  ]

  defp metrics(module) do
    @opts |> module.event_metrics() |> List.wrap() |> Enum.flat_map(& &1.metrics)
  end

  defp request_counter() do
    Enum.find(metrics(Plugin), &(&1.name == List.last(@relabelled)))
  end

  defp tags(method) do
    conn = %{Plug.Test.conn("GET", "/api/docker") | method: method, host: "scanner.example"}
    request_counter().tag_values.(%{conn: conn})
  end

  test "returns the upstream metrics under the upstream names and groups" do
    ours = List.wrap(Plugin.event_metrics(@opts))
    upstream = List.wrap(Upstream.event_metrics(@opts))

    assert Enum.map(ours, & &1.group_name) == Enum.map(upstream, & &1.group_name)
    assert Enum.map(metrics(Plugin), & &1.name) == Enum.map(metrics(Upstream), & &1.name)
    assert Plugin.polling_metrics(@opts) == Upstream.polling_metrics(@opts)
  end

  test "drops the host label from the HTTP metrics and keeps the rest" do
    upstream = Map.new(metrics(Upstream), &{&1.name, &1})

    for ours <- metrics(Plugin), ours.name in @relabelled do
      assert :host in upstream[ours.name].tags
      assert ours.tags == List.delete(upstream[ours.name].tags, :host)

      assert %{ours | tags: upstream[ours.name].tags, tag_values: upstream[ours.name].tag_values} ==
               upstream[ours.name]
    end
  end

  test "leaves every other upstream metric unchanged" do
    pairs = Enum.zip(metrics(Upstream), metrics(Plugin))

    for {upstream, ours} <- pairs, upstream.name not in @relabelled do
      assert ours == upstream
    end
  end

  test "keeps the standard methods and labels any other OTHER" do
    for method <- ~w(GET HEAD POST PUT PATCH DELETE OPTIONS) do
      assert tags(method).method == method
    end

    for method <- ~w(PROPFIND get SSTP_DUPLEX_POST) do
      assert tags(method).method == "OTHER"
    end

    refute Map.has_key?(tags("GET"), :host)
  end

  test "labels a request's route and status but not its host", %{conn: conn} do
    name = :"#{__MODULE__}.Metrics"
    start_supervised!(PromEx.Storage.Core.child_spec(name, metrics(Plugin)))
    conn = %{conn | host: "scanner.example"}

    assert json_response(get(conn, "/api/docker"), 200)

    assert response(dispatch(conn, BobWeb.Endpoint, "PROPFIND", "/"), 404)

    scrape = PromEx.Storage.Core.scrape(name)

    assert scrape =~
             ~s(bob_prom_ex_phoenix_http_requests_total{action="docker_tags",controller="BobWeb.PublicApiController",method="GET",path="/api/docker",status="200"} 1\n)

    assert scrape =~
             ~s(bob_prom_ex_phoenix_http_requests_total{action="Unknown",controller="Unknown",method="OTHER",path="Unknown",status="404"} 1\n)

    refute scrape =~ "scanner.example"
    refute scrape =~ "PROPFIND"
  end
end
