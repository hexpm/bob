defmodule Bob.PromEx.Plugins.Ecto do
  @moduledoc """
  `PromEx.Plugins.Ecto` with query time and row count buckets that resolve
  the queries run here.

  The upstream plugin hardcodes its buckets and offers no option to change
  them. Its query time histograms start at 10 ms (5 ms for decoding), and a
  query here waits about 1 ms for a connection and runs in about 1 ms, so
  nearly every query lands in the lowest bucket. Its row count histogram stops
  at 1,000 rows, and the daily reconcile deletes about a million staged Docker
  tags in one statement.

  The upstream metrics are returned under their own names with only those
  buckets replaced, so the upstream Ecto dashboard keeps working. The time
  buckets keep 250 ms, the queue time's p99 threshold in DbCheckoutWaitHigh.
  """

  use PromEx.Plugin

  alias PromEx.MetricTypes.Event
  alias Telemetry.Metrics.Distribution

  @time_buckets [0.1, 0.25, 0.5, 1, 2.5, 5, 10, 50, 250, 1_000, 2_500, 10_000, 30_000]

  @rows_buckets [5, 10, 50, 100, 500, 1_000, 10_000, 100_000, 1_000_000, 10_000_000]

  @rebucketed %{
    [:repo, :query, :idle, :time, :milliseconds] => @time_buckets,
    [:repo, :query, :queue, :time, :milliseconds] => @time_buckets,
    [:repo, :query, :decode, :time, :milliseconds] => @time_buckets,
    [:repo, :query, :execution, :time, :milliseconds] => @time_buckets,
    [:repo, :query, :total, :time, :milliseconds] => @time_buckets,
    [:repo, :query, :results, :returned] => @rows_buckets
  }

  @impl true
  def event_metrics(opts) do
    opts
    |> PromEx.Plugins.Ecto.event_metrics()
    |> Enum.map(&rebucket/1)
  end

  @impl true
  def polling_metrics(opts), do: PromEx.Plugins.Ecto.polling_metrics(opts)

  defp rebucket(%Event{metrics: metrics} = event) do
    %{event | metrics: Enum.map(metrics, &rebucket_metric/1)}
  end

  defp rebucket_metric(%Distribution{name: name, reporter_options: options} = metric) do
    case Enum.find(@rebucketed, fn {suffix, _buckets} -> List.ends_with?(name, suffix) end) do
      {_suffix, buckets} -> %{metric | reporter_options: Keyword.put(options, :buckets, buckets)}
      nil -> metric
    end
  end

  defp rebucket_metric(metric), do: metric
end
