defmodule Bob.Job.Reconcile do
  def run() do
    Bob.Reconcile.reconcile()
  end

  def priority(), do: 1
  def weight(), do: 1
  def concurrency(), do: :shared
end
