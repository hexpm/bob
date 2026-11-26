defmodule Bob.Queue do
  import Ecto.Query
  require Logger

  alias Bob.Repo
  alias Bob.Queue.{Job, Failure, Term}

  @backoff_base 30 * 60
  @backoff_max 24 * 60 * 60

  # Periodic scheduler jobs re-run every interval and must not be suppressed by
  # backoff after a transient failure; only the build jobs they enqueue back off.
  # A builds purge is queued once per uploaded artifact and nothing re-queues it,
  # so backing off after a failed purge would skip the next build's purge of the
  # same keys.
  @no_backoff [
    Bob.Job.OTPChecker,
    Bob.Job.DockerChecker,
    Bob.Job.Reconcile,
    Bob.Job.ReconcileBaseImages,
    Bob.Job.DockerCleanup,
    Bob.Job.PurgeBuilds
  ]

  @dedup_conflict_target {:unsafe_fragment,
                          "(module_key, args_digest) WHERE state IN ('queued', 'running')"}

  # Postgres rejects a statement with more than 65535 bind parameters. Each row
  # inserted below binds 8 fields, so chunk inserts to stay under that ceiling.
  @insert_chunk_size div(65_535, 8)

  def add(key, args) do
    add_many([{key, args}])
  end

  @priorities %{normal: 0, request: 1}

  @doc """
  Queues `{key, args}` entries, skipping any that are already queued or running.

  The `:priority` option is `:normal` (the default) or `:request`. Jobs of a key
  are claimed `:request` jobs first, then by the job module's `released_at/1`,
  newest first and jobs without one last, then oldest queued first. Adding a
  job that is already queued at a lower priority raises its priority.
  """
  def add_many(entries, opts \\ []) do
    priority = Map.fetch!(@priorities, Keyword.get(opts, :priority, :normal))
    now = DateTime.utc_now()

    rows =
      entries
      |> Enum.map(fn {key, args} ->
        %{module_key: key, args: args, args_digest: Term.digest(args)}
      end)
      |> reject_backed_off(now)
      |> Enum.map(fn candidate ->
        Logger.info(%{
          message: "Job queued",
          event: "job.queued",
          job: inspect(candidate.module_key),
          job_args: inspect(candidate.args)
        })

        %{
          module_key: candidate.module_key,
          args: candidate.args,
          args_digest: candidate.args_digest,
          state: "queued",
          priority: priority,
          released_at: released_at(candidate.module_key, candidate.args),
          inserted_at: now,
          updated_at: now
        }
      end)

    rows
    |> Enum.chunk_every(@insert_chunk_size)
    |> Enum.each(fn chunk ->
      Repo.insert_all(Job, chunk,
        on_conflict: on_conflict(priority),
        conflict_target: @dedup_conflict_target
      )
    end)

    broadcast()
    :ok
  end

  # released_at/1 gets the same arguments as the job's run, which takes the
  # key's argument first.
  defp released_at(key, args) do
    {module, run_args} =
      case key do
        {module, arg} -> {module, [arg | args]}
        module -> {module, args}
      end

    if Code.ensure_loaded?(module) and function_exported?(module, :released_at, 1) do
      module.released_at(run_args)
    end
  end

  defp on_conflict(0), do: :nothing

  defp on_conflict(_priority) do
    from(j in Job,
      update: [set: [priority: fragment("GREATEST(?, EXCLUDED.priority)", j.priority)]]
    )
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
          ORDER BY priority DESC, released_at DESC NULLS LAST, inserted_at, id
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

        Logger.info(%{
          message: "Job claimed",
          event: "job.claimed",
          job: inspect(key),
          job_args: inspect(args)
        })

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
          Logger.info(%{
            message: "Job succeeded",
            event: "job.succeeded",
            job: inspect(module_key),
            job_args: inspect(args)
          })

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
          Logger.info(%{
            message: "Job failed",
            event: "job.failed",
            job: inspect(module_key),
            job_args: inspect(args)
          })

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
  broken. The row keeps its `inserted_at`, `priority` and `released_at`, so
  it returns to its place in the queue and is picked up as soon as a runner
  polls.
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
        Logger.info(%{
          message: "Job requeued",
          event: "job.requeued",
          job: inspect(module_key),
          job_args: inspect(args)
        })

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

  @doc "Lists queued jobs as `{module_key, args}` in claim order, for inspection."
  def queued() do
    Repo.all(
      from(j in Job,
        where: j.state == "queued",
        order_by: [
          desc: j.priority,
          desc_nulls_last: j.released_at,
          asc: j.inserted_at,
          asc: j.id
        ],
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
        order_by: [
          desc: j.priority,
          desc_nulls_last: j.released_at,
          asc: j.inserted_at,
          asc: j.id
        ],
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
            Logger.info(%{
              message: "Job backed off",
              event: "job.backoff",
              job: inspect(candidate.module_key),
              job_args: inspect(candidate.args)
            })
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
