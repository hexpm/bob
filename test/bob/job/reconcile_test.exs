defmodule Bob.Job.ReconcileTest do
  use ExUnit.Case, async: true

  alias Bob.Job.Reconcile

  test "exposes the runner callbacks" do
    assert Reconcile.priority() == 1
    assert Reconcile.weight() == 1
    assert Reconcile.concurrency() == :shared
    assert function_exported?(Reconcile, :run, 0)
  end
end
