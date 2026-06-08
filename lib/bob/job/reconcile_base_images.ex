defmodule Bob.Job.ReconcileBaseImages do
  def run() do
    Bob.Reconcile.reconcile_base_images()
  end

  def priority(), do: 1
  def weight(), do: 1
  def concurrency(), do: :shared
end
