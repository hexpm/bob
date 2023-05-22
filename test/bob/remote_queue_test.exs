defmodule Bob.RemoteQueueTest do
  use ExUnit.Case

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
    setup do
      Bob.Queue.reset()
    end

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
  end
end
