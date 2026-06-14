defmodule Bob.Queue do
  import Ecto.Query
  require Logger

  alias Bob.Repo
  alias Bob.Queue.{Job, Failure, Term}

  @backoff_base 30 * 60
  @backoff_max 24 * 60 * 60

  # Periodic scheduler jobs re-run every interval and must not be suppressed by
  # backoff after a transient failure; only the build jobs they enqueue back off.
  @no_backoff [
    Bob.Job.OTPChecker,
    Bob.Job.DockerChecker,
    Bob.Job.Reconcile,
    Bob.Job.ReconcileBaseImages
  ]

  @dedup_conflict_target {:unsafe_fragment,
                          "(module_key, args_digest) WHERE state IN ('queued', 'running')"}

  # Postgres rejects a statement with more than 65535 bind parameters. Each row
  # inserted below binds 6 fields, so chunk inserts to stay under that ceiling.
  @insert_chunk_size div(65_535, 6)

  def add(key, args) do
    add_many([{key, args}])
  end

  def add_many(entries) do
    now = DateTime.utc_now()

    rows =
      entries
      |> Enum.map(fn {key, args} ->
        %{module_key: key, args: args, args_digest: Term.digest(args)}
      end)
      |> reject_backed_off(now)
      |> Enum.map(fn candidate ->
        Logger.info("QUEUED #{inspect(candidate.module_key)} #{inspect(candidate.args)}")

        %{
          module_key: candidate.module_key,
          args: candidate.args,
          args_digest: candidate.args_digest,
          state: "queued",
          inserted_at: now,
          updated_at: now
        }
      end)

    rows
    |> Enum.chunk_every(@insert_chunk_size)
    |> Enum.each(fn chunk ->
      Repo.insert_all(Job, chunk,
        on_conflict: :nothing,
        conflict_target: @dedup_conflict_target
      )
    end)

    broadcast()
    :ok
  end

  def start(key) do
    module_key = Term.encode(key)
    now = NaiveDateTime.utc_now()

    {:ok, %{rows: rows}} =
      Repo.query(
        """
        WITH candidate AS (
          SELECT id FROM jobs
          WHERE state = 'queued' AND module_key = $1
          ORDER BY inserted_at, id
          FOR UPDATE SKIP LOCKED
          LIMIT 1
        )
        UPDATE jobs SET state = 'running', started_at = $2, updated_at = $2
        FROM candidate WHERE jobs.id = candidate.id
        RETURNING jobs.id, jobs.args
        """,
        [module_key, now]
      )

    case rows do
      [[id, args_binary]] ->
        args = Term.decode(args_binary)
        Logger.info("STARTING #{inspect(key)} #{inspect(args)}")
        broadcast()
        {:ok, {id, args}}

      [] ->
        :error
    end
  end

  def success(id) do
    Repo.transaction(fn ->
      case finish(id, "done") do
        {:ok, module_key, args_digest, args} ->
          Logger.info("SUCCESS #{inspect(module_key)} #{inspect(args)}")

          Repo.delete_all(
            from(f in Failure,
              where: f.module_key == ^module_key and f.args_digest == ^args_digest
            )
          )

        :error ->
          :ok
      end
    end)

    broadcast()
    :ok
  end

  def failure(id) do
    Repo.transaction(fn ->
      case finish(id, "failed") do
        {:ok, module_key, args_digest, args} ->
          Logger.info("FAILURE #{inspect(module_key)} #{inspect(args)}")
          if backoff?(module_key), do: record_failure(module_key, args_digest)

        :error ->
          :ok
      end
    end)

    broadcast()
    :ok
  end

  @doc """
  Puts a running job back in the queue, e.g. when its node shuts down mid-run.

  Unlike `failure/1` this records no backoff — the job was interrupted, not
  broken. The row keeps its `inserted_at`, so it returns to the front of the
  FIFO and is picked up as soon as a runner polls.
  """
  def requeue(id) do
    now = DateTime.utc_now()

    {_count, rows} =
      Repo.update_all(
        from(j in Job,
          where: j.id == ^id and j.state == "running",
          select: {j.module_key, j.args}
        ),
        set: [state: "queued", started_at: nil, updated_at: now]
      )

    case rows do
      [{module_key, args}] ->
        Logger.info("REQUEUED #{inspect(module_key)} #{inspect(args)}")
        broadcast()

      [] ->
        :ok
    end

    :ok
  end

  def queue_sizes() do
    Repo.all(
      from(j in Job,
        where: j.state == "queued",
        group_by: j.module_key,
        select: {j.module_key, count(j.id)}
      )
    )
  end

  @doc "Lists queued jobs as `{module_key, args}`, oldest first, for inspection."
  def queued() do
    Repo.all(
      from(j in Job,
        where: j.state == "queued",
        order_by: [j.inserted_at, j.id],
        select: {j.module_key, j.args}
      )
    )
  end

  def running(modules \\ []) do
    Repo.all(
      from(j in Job,
        where: j.state == "running",
        order_by: [desc: j.started_at, desc: j.id]
      )
      |> filter_modules(modules)
    )
  end

  def queued_listing(limit \\ 100, offset \\ 0, modules \\ []) do
    Repo.all(
      from(j in Job,
        where: j.state == "queued",
        order_by: [j.inserted_at, j.id],
        limit: ^limit,
        offset: ^offset
      )
      |> filter_modules(modules)
    )
  end

  def finished_count(modules \\ []) do
    from(j in Job, where: j.state in ["done", "failed"])
    |> filter_modules(modules)
    |> Repo.aggregate(:count, :id)
  end

  def recent(limit \\ 50, offset \\ 0, modules \\ []) do
    Repo.all(
      from(j in Job,
        where: j.state in ["done", "failed"],
        order_by: [desc: j.finished_at, desc: j.id],
        limit: ^limit,
        offset: ^offset
      )
      |> filter_modules(modules)
    )
  end

  @doc "Lists the distinct job modules present in the queue, in any state."
  def job_modules() do
    Repo.all(from(j in Job, distinct: true, select: j.module_key))
    |> Enum.sort_by(&inspect/1)
  end

  defp filter_modules(query, []), do: query

  defp filter_modules(query, modules) do
    # A module key can be a `{module, key}` tuple, and a list of those reads as a
    # keyword list, which Ecto's `in` rejects. Match each key with `==` so the
    # Term type dumps it as a single value instead.
    conditions =
      Enum.reduce(modules, dynamic(false), fn module, acc ->
        dynamic([j], ^acc or j.module_key == ^module)
      end)

    where(query, ^conditions)
  end

  defp finish(id, state) do
    now = DateTime.utc_now()

    {_count, rows} =
      Repo.update_all(
        from(j in Job,
          where: j.id == ^id and j.state == "running",
          select: {j.module_key, j.args_digest, j.args}
        ),
        set: [state: state, finished_at: now, updated_at: now]
      )

    case rows do
      [{module_key, args_digest, args}] -> {:ok, module_key, args_digest, args}
      [] -> :error
    end
  end

  defp record_failure(module_key, args_digest) do
    Repo.query!(
      """
      INSERT INTO job_failures (module_key, args_digest, count, last_failed_at, inserted_at, updated_at)
      VALUES ($1, $2, 1, $3, $3, $3)
      ON CONFLICT (module_key, args_digest)
      DO UPDATE SET count = job_failures.count + 1, last_failed_at = $3, updated_at = $3
      """,
      [Term.encode(module_key), args_digest, NaiveDateTime.utc_now()]
    )
  end

  defp backoff?(module_key) do
    module =
      case module_key do
        {module, _arg} -> module
        module -> module
      end

    module not in @no_backoff
  end

  defp reject_backed_off(candidates, now) do
    digests = candidates |> Enum.map(& &1.args_digest) |> Enum.uniq()

    failures =
      Repo.all(
        from(f in Failure,
          where: f.args_digest in ^digests,
          select: {f.module_key, f.args_digest, f.count, f.last_failed_at}
        )
      )
      |> Map.new(fn {module_key, args_digest, count, last_failed_at} ->
        {{module_key, args_digest}, {count, last_failed_at}}
      end)

    Enum.reject(candidates, fn candidate ->
      case Map.fetch(failures, {candidate.module_key, candidate.args_digest}) do
        {:ok, {count, last_failed_at}} ->
          backed_off? = DateTime.diff(now, last_failed_at) < backoff_seconds(count)

          if backed_off? do
            Logger.info("BACKOFF #{inspect(candidate.module_key)} #{inspect(candidate.args)}")
          end

          backed_off?

        :error ->
          false
      end
    end)
  end

  defp backoff_seconds(count) do
    min(@backoff_base * Integer.pow(2, min(count - 1, 12)), @backoff_max)
  end

  defp broadcast() do
    Phoenix.PubSub.broadcast(Bob.PubSub, "jobs", :jobs_changed)
  end
end
