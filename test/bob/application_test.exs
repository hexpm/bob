defmodule Bob.ApplicationTest do
  use ExUnit.Case, async: true

  test "PromEx starts before the repo so it sees the repo's init telemetry" do
    children = Bob.Application.children()

    assert Enum.find_index(children, &(&1 == Bob.PromEx)) <
             Enum.find_index(children, &(&1 == Bob.Repo))
  end

  test "starts the counters at zero after PromEx and before what emits their events" do
    children = Bob.Application.children()
    index = &Enum.find_index(children, &1)

    prom_ex = index.(&(&1 == Bob.PromEx))
    jobs = index.(&match?(%{id: {Bob.PromEx.Plugins.Bob, :initialize_counters}}, &1))
    pool = index.(&match?(%{id: {Bob.PromEx.Plugins.DbConnection, :initialize_counters}}, &1))

    assert prom_ex < jobs
    assert jobs < index.(&match?(%{id: :runner}, &1))
    assert jobs < index.(&(&1 == BobWeb.Endpoint))
    assert prom_ex < pool
    assert pool < index.(&match?({DBConnection.TelemetryListener, _opts}, &1))
    assert pool < index.(&(&1 == Bob.Repo))
  end
end
