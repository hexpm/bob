defmodule Bob.Job.ReconcileBaseImages do
  def run() do
    Bob.Reconcile.reconcile_base_images()
  end
end
