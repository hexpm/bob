defmodule Bob.PromEx.Plugins.DbConnection do
  @moduledoc """
  PromEx plugin for the database connection pool: refused checkouts and
  connection churn.

  `[:db_connection, :connection_error]` fires where the pool gives up on a
  checkout. The reason is `:queue_timeout` when the caller waited out the queue
  and `:error` when there was no connection to wait for. Connects and
  disconnects come from the `DBConnection.TelemetryListener` the repo is
  started with.

  A counter series is created by its first event, and Prometheus' `increase()`
  needs two samples, so it never counts that first event. The counters are sums
  of each event's `:count` measurement, 1 when absent, and
  `initialize_counters/0` creates every series at zero before the repo starts.
  """

  use PromEx.Plugin

  @impl true
  def event_metrics(opts) do
    otp_app = Keyword.fetch!(opts, :otp_app)

    metric_prefix =
      Keyword.get(opts, :metric_prefix, PromEx.metric_prefix(otp_app, :db_connection))

    Event.build(:bob_db_connection_event_metrics, [
      sum(
        metric_prefix ++ [:connection_error, :total],
        event_name: [:db_connection, :connection_error],
        measurement: &__MODULE__.count/1,
        description: "Connection checkouts the pool refused, by reason.",
        tags: [:reason],
        tag_values: &__MODULE__.error_tags/1
      ),
      sum(
        metric_prefix ++ [:connected, :total],
        event_name: [:db_connection, :connected],
        measurement: &__MODULE__.count/1,
        description: "Database connections established."
      ),
      sum(
        metric_prefix ++ [:disconnected, :total],
        event_name: [:db_connection, :disconnected],
        measurement: &__MODULE__.count/1,
        description: "Database connections lost or closed."
      )
    ])
  end

  def error_tags(%{error: %DBConnection.ConnectionError{reason: reason}}), do: %{reason: reason}
  def error_tags(_metadata), do: %{reason: :unknown}

  @doc false
  def count(measurements), do: Map.get(measurements, :count, 1)

  @doc """
  Reports a zero for every counter series, so the first refused checkout or
  dropped connection is an increase Prometheus can see. Started as a child
  right before the repo, on the master like this plugin.
  """
  def initialize_counters() do
    for reason <- [:queue_timeout, :error] do
      :telemetry.execute([:db_connection, :connection_error], %{count: 0}, %{
        error: %DBConnection.ConnectionError{reason: reason}
      })
    end

    :telemetry.execute([:db_connection, :connected], %{count: 0}, %{})
    :telemetry.execute([:db_connection, :disconnected], %{count: 0}, %{})

    :ignore
  end
end
