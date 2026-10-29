defmodule Bob.PromEx.Plugins.EctoTest do
  # The query test collects every query Bob.Repo runs, so it runs apart from
  # the async tests that query.
  use Bob.DataCase, async: false

  alias Bob.PromEx.Plugins.Ecto, as: Plugin
  alias PromEx.Plugins.Ecto, as: Upstream

  @opts [otp_app: :bob, repos: [Bob.Repo]]

  @prefix [:bob, :prom_ex, :ecto, :repo, :query]

  @times [
    @prefix ++ [:idle, :time, :milliseconds],
    @prefix ++ [:queue, :time, :milliseconds],
    @prefix ++ [:decode, :time, :milliseconds],
    @prefix ++ [:execution, :time, :milliseconds],
    @prefix ++ [:total, :time, :milliseconds]
  ]

  @rows @prefix ++ [:results, :returned]

  defp metrics(module) do
    @opts |> module.event_metrics() |> List.wrap() |> Enum.flat_map(& &1.metrics)
  end

  defp buckets(module) do
    Map.new(metrics(module), &{&1.name, &1.reporter_options[:buckets]})
  end

  test "returns the upstream metrics under the upstream names and groups" do
    ours = List.wrap(Plugin.event_metrics(@opts))
    upstream = List.wrap(Upstream.event_metrics(@opts))

    assert Enum.map(ours, & &1.group_name) == Enum.map(upstream, & &1.group_name)
    assert Enum.map(metrics(Plugin), & &1.name) == Enum.map(metrics(Upstream), & &1.name)
    assert Plugin.polling_metrics(@opts) == Upstream.polling_metrics(@opts)
  end

  test "resolves query times below the upstream's lowest bucket and keeps its ceiling" do
    ours = buckets(Plugin)
    upstream = buckets(Upstream)

    for name <- @times do
      assert ours[name] == Enum.sort(ours[name])
      assert Enum.min(ours[name]) < 1
      assert Enum.max(ours[name]) >= Enum.max(upstream[name])
      assert 250 in ours[name], "DbCheckoutWaitHigh compares the p99 against 250 ms"
    end
  end

  test "counts results past the upstream's 1,000 rows" do
    ours = buckets(Plugin)[@rows]

    assert ours == Enum.sort(ours)
    assert List.starts_with?(ours, buckets(Upstream)[@rows])
    assert Enum.max(ours) >= 1_000_000
  end

  test "leaves every other upstream metric unchanged" do
    pairs = Enum.zip(metrics(Upstream), metrics(Plugin))

    for {upstream, ours} <- pairs do
      if upstream.name in [@rows | @times] do
        assert %{ours | reporter_options: upstream.reporter_options} == upstream
      else
        assert ours == upstream
      end
    end
  end

  test "reports a query in the finer buckets" do
    name = :"#{__MODULE__}.Metrics"
    start_supervised!(PromEx.Storage.Core.child_spec(name, metrics(Plugin)))

    Repo.query!("SELECT 1")

    series =
      ~r/bob_prom_ex_ecto_repo_query_execution_time_milliseconds_bucket\{command="select",repo="Bob.Repo",source="source_unavailable",le="([^"]+)"\} (\d+)\n/
      |> Regex.scan(PromEx.Storage.Core.scrape(name), capture: :all_but_first)

    assert Enum.map(series, &hd/1) ==
             ~w(0.1 0.25 0.5 1 2.5 5 10 50 250 1000 2500 10000 30000 +Inf)

    assert List.last(series) == ["+Inf", "1"]
  end
end
