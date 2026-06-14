defmodule Bob.Queue.MaintenanceTest do
  use Bob.DataCase

  alias Bob.Queue.{Maintenance, Job, Failure, Term}

  @hour 60 * 60
  @day 24 * @hour

  defp insert_job(attrs) do
    now = DateTime.utc_now()

    defaults = %{
      module_key: :test,
      args: [:a],
      args_digest: Term.digest([:a]),
      state: "queued",
      inserted_at: now,
      updated_at: now
    }

    Repo.insert_all(Job, [Map.merge(defaults, Map.new(attrs))])
  end

  defp insert_failure(attrs) do
    now = DateTime.utc_now()

    defaults = %{
      module_key: :test,
      args_digest: Term.digest([:a]),
      count: 1,
      last_failed_at: now,
      inserted_at: now,
      updated_at: now
    }

    Repo.insert_all(Failure, [Map.merge(defaults, Map.new(attrs))])
  end

  defp ago(seconds), do: DateTime.add(DateTime.utc_now(), -seconds, :second)

  test "requeues stale running jobs without recording backoff" do
    old = ago(4 * @hour)
    insert_job(state: "running", inserted_at: old, started_at: old)

    Maintenance.run()

    assert [%Job{state: "queued", started_at: nil, requeues: 1, inserted_at: inserted}] =
             Repo.all(Job)

    # inserted_at is kept so the requeued job stays at the front of the queue.
    assert DateTime.compare(inserted, old) == :eq
    assert Repo.all(Failure) == []
  end

  test "fails a stale running job once its requeues are exhausted" do
    old = ago(4 * @hour)
    insert_job(state: "running", inserted_at: old, started_at: old, requeues: 2)

    Maintenance.run()

    assert [%Job{state: "failed", finished_at: finished, requeues: 2}] = Repo.all(Job)
    assert finished != nil
    assert Repo.all(Failure) == []
  end

  test "leaves running jobs that are within the timeout" do
    now = DateTime.utc_now()
    insert_job(state: "running", inserted_at: now, started_at: now)

    Maintenance.run()

    assert [%Job{state: "running"}] = Repo.all(Job)
  end

  test "prunes failures older than the expiry window" do
    insert_failure(last_failed_at: ago(8 * @day))

    Maintenance.run()

    assert Repo.all(Failure) == []
  end

  test "keeps recent failures" do
    insert_failure(last_failed_at: DateTime.utc_now())

    Maintenance.run()

    assert [%Failure{}] = Repo.all(Failure)
  end

  test "prunes completed jobs past the retention window" do
    old = ago(91 * @day)
    insert_job(state: "done", inserted_at: old, finished_at: old)

    Maintenance.run()

    assert Repo.all(Job) == []
  end

  test "keeps recently completed jobs within the retention window" do
    now = DateTime.utc_now()
    insert_job(state: "done", inserted_at: now, finished_at: now)

    Maintenance.run()

    assert [%Job{state: "done"}] = Repo.all(Job)
  end

  test "keeps queued jobs regardless of age" do
    insert_job(state: "queued", inserted_at: ago(91 * @day))

    Maintenance.run()

    assert [%Job{state: "queued"}] = Repo.all(Job)
  end

  test "caps completed job history at the maximum, keeping the most recent" do
    Application.put_env(:bob, :history_max_jobs, 2)
    on_exit(fn -> Application.delete_env(:bob, :history_max_jobs) end)

    now = DateTime.utc_now()

    for i <- 1..4 do
      insert_job(state: "done", inserted_at: now, finished_at: DateTime.add(now, i, :second))
    end

    Maintenance.run()

    kept =
      Repo.all(from(j in Job, order_by: [asc: j.finished_at], select: j.finished_at))

    assert kept == [DateTime.add(now, 3, :second), DateTime.add(now, 4, :second)]
  end

  test "does not count queued or running jobs toward the history cap" do
    Application.put_env(:bob, :history_max_jobs, 2)
    on_exit(fn -> Application.delete_env(:bob, :history_max_jobs) end)

    now = DateTime.utc_now()
    insert_job(state: "queued", args: [:q], args_digest: Term.digest([:q]), inserted_at: now)

    insert_job(
      state: "running",
      args: [:r],
      args_digest: Term.digest([:r]),
      inserted_at: now,
      started_at: now
    )

    for i <- 1..3 do
      insert_job(state: "done", inserted_at: now, finished_at: DateTime.add(now, i, :second))
    end

    Maintenance.run()

    assert Repo.all(Job) |> Enum.frequencies_by(& &1.state) == %{
             "queued" => 1,
             "running" => 1,
             "done" => 2
           }
  end
end
