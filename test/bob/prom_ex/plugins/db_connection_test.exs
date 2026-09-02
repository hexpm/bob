defmodule Bob.PromEx.Plugins.DbConnectionTest do
  use ExUnit.Case, async: true

  alias Bob.PromEx.Plugins.DbConnection

  test "tags a refused checkout by its reason" do
    error = DBConnection.ConnectionError.exception("connection not available", :queue_timeout)

    assert DbConnection.error_tags(%{error: error}) == %{reason: :queue_timeout}
  end

  test "counts an error without a reason rather than dropping it" do
    assert DbConnection.error_tags(%{error: :closed}) == %{reason: :unknown}
  end

  test "attaches to the pool and listener events" do
    events =
      [otp_app: :bob]
      |> DbConnection.event_metrics()
      |> List.wrap()
      |> Enum.flat_map(& &1.metrics)
      |> Enum.map(& &1.event_name)
      |> Enum.uniq()

    assert [:db_connection, :connection_error] in events
    assert [:db_connection, :connected] in events
    assert [:db_connection, :disconnected] in events
  end

  test "the repo notifies the listener the application started" do
    assert Bob.Repo.config()[:connection_listeners] ==
             {[Bob.Repo.TelemetryListener], Bob.Repo}
  end

  test "the listener reports connections the repo opens and closes" do
    ref = make_ref()
    parent = self()

    :telemetry.attach_many(
      {__MODULE__, ref},
      [[:db_connection, :connected], [:db_connection, :disconnected]],
      fn event, _measurements, metadata, _config -> send(parent, {ref, event, metadata.tag}) end,
      nil
    )

    on_exit(fn -> :telemetry.detach({__MODULE__, ref}) end)

    {:ok, repo} = Bob.Repo.start_link(name: __MODULE__.Repo, pool_size: 1)
    assert_receive {^ref, [:db_connection, :connected], Bob.Repo}, 5_000

    Supervisor.stop(repo)
    assert_receive {^ref, [:db_connection, :disconnected], Bob.Repo}, 5_000
  end
end
