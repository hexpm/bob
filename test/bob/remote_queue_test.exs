defmodule Bob.RemoteQueueTest do
  use Bob.DataCase

  alias Bob.RemoteQueue

  defmodule SharedTestJob do
    require Logger

    def priority(), do: 2
    def weight(), do: 4
    def concurrency(), do: :shared
  end

  defmodule UnsharedTestJob do
    require Logger

    def priority(), do: 2
    def weight(), do: 4
    def concurrency(), do: __MODULE__
  end

  describe "start_jobs/3" do
    test "start single job" do
      Bob.Queue.add(SharedTestJob, [:arg1])

      assert [{_id, SharedTestJob, [:arg1]}] = RemoteQueue.start_jobs([SharedTestJob], 100, %{})
    end

    test "start multiple jobs" do
      Bob.Queue.add(SharedTestJob, [:arg1])
      Bob.Queue.add(SharedTestJob, [:arg2])
      Bob.Queue.add(SharedTestJob, [:arg3])

      assert [
               {_id1, SharedTestJob, [:arg1]},
               {_id2, SharedTestJob, [:arg2]},
               {_id3, SharedTestJob, [:arg3]}
             ] = RemoteQueue.start_jobs([SharedTestJob], 100, %{})
    end

    test "dont start unless queued" do
      assert [] = RemoteQueue.start_jobs([SharedTestJob], 100, %{})
    end

    test "dont start when weight is too high" do
      Bob.Queue.add(SharedTestJob, [:arg1])
      assert [] = RemoteQueue.start_jobs([SharedTestJob], 3, %{})
    end

    test "only start one before weight is too high" do
      Bob.Queue.add(SharedTestJob, [:arg1])
      Bob.Queue.add(SharedTestJob, [:arg2])
      Bob.Queue.add(SharedTestJob, [:arg3])

      assert [{_id1, SharedTestJob, [:arg1]}] = RemoteQueue.start_jobs([SharedTestJob], 5, %{})
      assert [{_id1, SharedTestJob, [:arg2]}] = RemoteQueue.start_jobs([SharedTestJob], 4, %{})
    end

    test "jobs with different keys do not share weights" do
      Bob.Queue.add(SharedTestJob, [:arg1])
      Bob.Queue.add(SharedTestJob, [:arg2])
      Bob.Queue.add(UnsharedTestJob, [:arg1])
      Bob.Queue.add(UnsharedTestJob, [:arg2])

      assert [{_id1, SharedTestJob, [:arg1]}, {_id2, UnsharedTestJob, [:arg1]}] =
               RemoteQueue.start_jobs([SharedTestJob, UnsharedTestJob], 5, %{})
    end

    test "starts every queued master checker job (each implements the job contract)" do
      for module <- [
            Bob.Job.OTPChecker,
            Bob.Job.DockerChecker,
            Bob.Job.Reconcile,
            Bob.Job.ReconcileBaseImages
          ] do
        Bob.Queue.add(module, [])
        assert [{_id, ^module, []}] = RemoteQueue.start_jobs([module], 100, %{})
      end
    end
  end
end
