defmodule Bob.QueueTest do
  use Bob.DataCase

  alias Bob.Queue

  defmodule TestJob do
    def priority(), do: 1
    def weight(), do: 1
    def concurrency(), do: :shared
  end

  defp size(key) do
    case Enum.find(Queue.queue_sizes(), fn {k, _} -> k == key end) do
      {_key, size} -> size
      nil -> 0
    end
  end

  test "queues a job and pops it with start" do
    Queue.add(TestJob, [:a])
    assert size(TestJob) == 1

    assert {:ok, {id, [:a]}} = Queue.start(TestJob)
    assert is_integer(id)
    assert size(TestJob) == 0
  end

  test "start returns :error when the queue is empty" do
    assert Queue.start(TestJob) == :error
  end

  test "advances updated_at on each transition while inserted_at stays fixed" do
    Queue.add(TestJob, [:a])
    queued = Repo.one(Bob.Queue.Job)
    assert queued.inserted_at == queued.updated_at

    {:ok, {id, [:a]}} = Queue.start(TestJob)
    started = Repo.get!(Bob.Queue.Job, id)
    assert started.inserted_at == queued.inserted_at
    assert DateTime.compare(started.updated_at, queued.updated_at) == :gt

    Queue.success(id)
    done = Repo.get!(Bob.Queue.Job, id)
    assert done.inserted_at == queued.inserted_at
    assert DateTime.compare(done.updated_at, started.updated_at) == :gt
  end

  test "dedups an identical job that is still queued" do
    Queue.add(TestJob, [:a])
    Queue.add(TestJob, [:a])
    assert size(TestJob) == 1
  end

  test "dedups an identical job that is currently running" do
    Queue.add(TestJob, [:a])
    {:ok, {_id, [:a]}} = Queue.start(TestJob)

    Queue.add(TestJob, [:a])
    assert size(TestJob) == 0
    assert Queue.start(TestJob) == :error
  end

  test "queues different args separately" do
    Queue.add(TestJob, [:a])
    Queue.add(TestJob, [:b])
    assert size(TestJob) == 2
  end

  test "pops jobs in FIFO order" do
    Queue.add(TestJob, [:a])
    Queue.add(TestJob, [:b])

    assert {:ok, {_, [:a]}} = Queue.start(TestJob)
    assert {:ok, {_, [:b]}} = Queue.start(TestJob)
  end

  test "a claimed job cannot be claimed again" do
    Queue.add(TestJob, [:a])
    assert {:ok, {_id, [:a]}} = Queue.start(TestJob)
    assert Queue.start(TestJob) == :error
  end

  test "re-adds a job after a successful run" do
    Queue.add(TestJob, [:a])
    {:ok, {id, [:a]}} = Queue.start(TestJob)
    Queue.success(id)

    Queue.add(TestJob, [:a])
    assert size(TestJob) == 1
  end

  test "backs off re-adding a job after a failure" do
    Queue.add(TestJob, [:a])
    {:ok, {id, [:a]}} = Queue.start(TestJob)
    Queue.failure(id)

    Queue.add(TestJob, [:a])
    assert size(TestJob) == 0
  end

  test "failure backoff only applies to the failed args" do
    Queue.add(TestJob, [:a])
    {:ok, {id, [:a]}} = Queue.start(TestJob)
    Queue.failure(id)

    Queue.add(TestJob, [:b])
    assert size(TestJob) == 1
  end

  test "scheduler jobs do not back off after a failure" do
    Queue.add(Bob.Job.DockerChecker, [])
    {:ok, {id, []}} = Queue.start(Bob.Job.DockerChecker)
    Queue.failure(id)

    Queue.add(Bob.Job.DockerChecker, [])
    assert size(Bob.Job.DockerChecker) == 1
  end

  test "success clears any existing backoff for the job" do
    # Set up a previously-failed job that is now running again, by inserting
    # the rows directly (a backed-off job will not re-enter the queue on its own).
    digest = Bob.Queue.Term.digest([:a])
    now = DateTime.utc_now()

    {1, [%{id: id}]} =
      Repo.insert_all(
        Bob.Queue.Job,
        [
          %{
            module_key: TestJob,
            args: [:a],
            args_digest: digest,
            state: "running",
            inserted_at: now,
            updated_at: now,
            started_at: now
          }
        ],
        returning: [:id]
      )

    Repo.insert_all(Bob.Queue.Failure, [
      %{
        module_key: TestJob,
        args_digest: digest,
        count: 2,
        last_failed_at: now,
        inserted_at: now,
        updated_at: now
      }
    ])

    Queue.success(id)

    assert Repo.all(Bob.Queue.Failure) == []

    # With the backoff cleared, the job can be re-queued immediately.
    Queue.add(TestJob, [:a])
    assert size(TestJob) == 1
  end

  test "success on an unknown id is a no-op" do
    assert Queue.success(-1) == :ok
  end

  test "failure on an unknown id is a no-op" do
    assert Queue.failure(-1) == :ok
  end

  test "double success does not re-finalize" do
    Queue.add(TestJob, [:a])
    {:ok, {id, [:a]}} = Queue.start(TestJob)
    assert Queue.success(id) == :ok
    assert Queue.success(id) == :ok
  end

  test "add_many enqueues several jobs in one call and dedups" do
    Queue.add_many([{TestJob, [:a]}, {TestJob, [:b]}, {TestJob, [:a]}])
    assert size(TestJob) == 2
  end

  test "queue_sizes counts queued jobs per key" do
    Queue.add(TestJob, [:a])
    Queue.add(TestJob, [:b])
    Queue.add({TestJob, :variant}, [:c])

    assert Enum.sort(Queue.queue_sizes()) ==
             Enum.sort([{TestJob, 2}, {{TestJob, :variant}, 1}])
  end

  test "queued lists queued jobs with decoded module_key and args, oldest first" do
    Queue.add(TestJob, [:a])
    Queue.add({TestJob, :variant}, [:b, :c])

    assert Queue.queued() == [{TestJob, [:a]}, {{TestJob, :variant}, [:b, :c]}]
  end
end
