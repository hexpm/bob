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

  test "add_many chunks inserts that exceed the Postgres bind-parameter limit" do
    # Each row binds 6 fields, so more than 65535 / 6 rows would overflow a
    # single insert statement. Chunking must keep every row enqueued.
    count = div(65_535, 6) + 1
    entries = for i <- 1..count, do: {TestJob, [i]}

    Queue.add_many(entries)
    assert size(TestJob) == count
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

  describe "pubsub broadcasts" do
    setup do
      Phoenix.PubSub.subscribe(Bob.PubSub, "jobs")
      :ok
    end

    test "add broadcasts :jobs_changed" do
      Bob.Queue.add(Bob.Job.OTPChecker, [:a])
      assert_receive :jobs_changed
    end

    test "start broadcasts :jobs_changed" do
      Bob.Queue.add(Bob.Job.OTPChecker, [:a])
      assert_receive :jobs_changed
      {:ok, _} = Bob.Queue.start(Bob.Job.OTPChecker)
      assert_receive :jobs_changed
    end

    test "success and failure broadcast :jobs_changed" do
      Bob.Queue.add(Bob.Job.OTPChecker, [:a])
      assert_receive :jobs_changed
      {:ok, {id, _}} = Bob.Queue.start(Bob.Job.OTPChecker)
      assert_receive :jobs_changed
      Bob.Queue.success(id)
      assert_receive :jobs_changed

      Bob.Queue.add(Bob.Job.OTPChecker, [:b])
      assert_receive :jobs_changed
      {:ok, {id2, _}} = Bob.Queue.start(Bob.Job.OTPChecker)
      assert_receive :jobs_changed
      Bob.Queue.failure(id2)
      assert_receive :jobs_changed
    end
  end

  describe "read functions" do
    test "running/0 returns running jobs newest-started first" do
      Bob.Queue.add(Bob.Job.OTPChecker, [:a])
      Bob.Queue.add(Bob.Job.OTPChecker, [:b])
      {:ok, _} = Bob.Queue.start(Bob.Job.OTPChecker)
      {:ok, _} = Bob.Queue.start(Bob.Job.OTPChecker)

      running = Bob.Queue.running()
      assert length(running) == 2
      assert Enum.all?(running, &(&1.state == "running"))
      assert hd(running).started_at >= List.last(running).started_at
    end

    test "queued_listing/2 returns queued jobs oldest-first with limit/offset" do
      for n <- 1..3, do: Bob.Queue.add(Bob.Job.OTPChecker, [n])

      assert [a, b] = Bob.Queue.queued_listing(2, 0)
      assert a.inserted_at <= b.inserted_at
      assert [_c] = Bob.Queue.queued_listing(2, 2)
    end

    test "recent/2 returns done and failed jobs newest-finished first" do
      Bob.Queue.add(Bob.Job.OTPChecker, [:done])
      {:ok, {id1, _}} = Bob.Queue.start(Bob.Job.OTPChecker)
      Bob.Queue.success(id1)

      Bob.Queue.add(Bob.Job.OTPChecker, [:fail])
      {:ok, {id2, _}} = Bob.Queue.start(Bob.Job.OTPChecker)
      Bob.Queue.failure(id2)

      recent = Bob.Queue.recent(50, 0)
      assert Enum.map(recent, & &1.state) |> Enum.sort() == ["done", "failed"]
      assert hd(recent).finished_at >= List.last(recent).finished_at
    end

    test "finished_count/0 counts done and failed jobs" do
      Bob.Queue.add(Bob.Job.OTPChecker, [:done])
      {:ok, {done_id, _}} = Bob.Queue.start(Bob.Job.OTPChecker)
      Bob.Queue.success(done_id)

      Bob.Queue.add(Bob.Job.OTPChecker, [:failed])
      {:ok, {failed_id, _}} = Bob.Queue.start(Bob.Job.OTPChecker)
      Bob.Queue.failure(failed_id)

      Bob.Queue.add(Bob.Job.OTPChecker, [:queued])

      assert Bob.Queue.finished_count() == 2
    end
  end

  describe "module filters" do
    test "queued_listing/3 filters by module" do
      Queue.add(TestJob, [:a])
      Queue.add({TestJob, :variant}, [:b])
      Queue.add(Bob.Job.OTPChecker, [:c])

      assert [j1, j2] = Queue.queued_listing(100, 0, [TestJob, {TestJob, :variant}])
      assert j1.module_key == TestJob
      assert j2.module_key == {TestJob, :variant}

      assert [j] = Queue.queued_listing(100, 0, [Bob.Job.OTPChecker])
      assert j.module_key == Bob.Job.OTPChecker

      assert length(Queue.queued_listing(100, 0, [])) == 3
    end

    test "running/1 filters by module" do
      Queue.add(TestJob, [:a])
      Queue.add(Bob.Job.OTPChecker, [:b])
      {:ok, _} = Queue.start(TestJob)
      {:ok, _} = Queue.start(Bob.Job.OTPChecker)

      assert [j] = Queue.running([TestJob])
      assert j.module_key == TestJob
      assert length(Queue.running([])) == 2
    end

    test "recent/3 and finished_count/1 filter by module" do
      Queue.add(TestJob, [:a])
      {:ok, {id, _}} = Queue.start(TestJob)
      Queue.success(id)

      Queue.add(Bob.Job.OTPChecker, [:b])
      {:ok, {id, _}} = Queue.start(Bob.Job.OTPChecker)
      Queue.failure(id)

      assert [j] = Queue.recent(50, 0, [TestJob])
      assert j.module_key == TestJob
      assert Queue.finished_count([TestJob]) == 1
      assert Queue.finished_count([]) == 2
    end

    test "job_modules/0 lists distinct modules across all states" do
      Queue.add(TestJob, [:a])
      Queue.add(TestJob, [:b])
      Queue.add({TestJob, :variant}, [:c])
      {:ok, {id, _}} = Queue.start(TestJob)
      Queue.success(id)

      assert Queue.job_modules() == [TestJob, {TestJob, :variant}]
    end
  end
end
