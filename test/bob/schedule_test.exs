defmodule Bob.ScheduleTest do
  use Bob.DataCase

  defmodule TestJob do
    def priority(), do: 1
    def weight(), do: 1
    def concurrency(), do: :shared
  end

  test "concurrent schedulers enqueue a tick only once" do
    message = {:run, TestJob, [], nil, {15, :min}, true}

    Bob.Schedule.handle_info(message, [])
    Bob.Schedule.handle_info(message, [])

    assert [{TestJob, []}] = Bob.Queue.queued()
  end

  test "a tick is not re-enqueued after the job completed within the period" do
    message = {:run, TestJob, [], nil, {15, :min}, true}

    Bob.Schedule.handle_info(message, [])
    {:ok, {id, []}} = Bob.Queue.start(TestJob)
    Bob.Queue.success(id)

    Bob.Schedule.handle_info(message, [])

    assert Bob.Queue.queued() == []
  end
end
