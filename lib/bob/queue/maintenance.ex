defmodule Bob.Queue.Maintenance do
  @moduledoc """
  Periodic queue maintenance, guarded by a Postgres advisory lock so exactly
  one master instance does the work: requeues stale running jobs (failing them
  once their requeues are exhausted), prunes expired backoff rows, and prunes
  old job history.
  """

  use GenServer
  import Ecto.Query
  require Logger

  alias Bob.Repo
  alias Bob.Queue.{Job, Failure}

  @interval_seconds 60
  @job_timeout_seconds 3 * 60 * 60
  # A job stuck in running this long means its node died hard (OOM, node loss),
  # so the work itself is not suspect — requeue it. The cap stops a job that
  # reliably kills its node or genuinely exceeds the timeout from looping.
  @max_timeout_requeues 2
  @backoff_expiry_seconds 7 * 24 * 60 * 60
  @history_retention_seconds 90 * 24 * 60 * 60
  @advisory_lock_key 4_771_001

  def start_link([]) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init([]) do
    schedule_tick()
    {:ok, []}
  end

  @impl true
  def handle_info(:tick, state) do
    run()
    schedule_tick()
    {:noreply, state}
  end

  @doc false
  def run() do
    {:ok, _} =
      Repo.transaction(fn ->
        if locked?() do
          sweep_stale_running()
          prune_failures()
          prune_history()
        end
      end)

    :ok
  end

  defp locked?() do
    %{rows: [[locked?]]} =
      Repo.query!("SELECT pg_try_advisory_xact_lock($1)", [@advisory_lock_key])

    locked?
  end

  defp sweep_stale_running() do
    now = DateTime.utc_now()
    cutoff = DateTime.add(now, -@job_timeout_seconds, :second)

    stale =
      from(j in Job,
        where: j.state == "running" and not is_nil(j.started_at) and j.started_at < ^cutoff
      )

    {requeued, _} =
      Repo.update_all(
        from(j in stale, where: j.requeues < @max_timeout_requeues),
        set: [state: "queued", started_at: nil, updated_at: now],
        inc: [requeues: 1]
      )

    {failed, _} =
      Repo.update_all(
        from(j in stale, where: j.requeues >= @max_timeout_requeues),
        set: [state: "failed", finished_at: now, updated_at: now]
      )

    if requeued > 0 or failed > 0 do
      Logger.info("SWEEP requeued #{requeued} and timed out #{failed} running job(s)")
    end
  end

  defp prune_failures() do
    cutoff = DateTime.add(DateTime.utc_now(), -@backoff_expiry_seconds, :second)
    Repo.delete_all(from(f in Failure, where: f.last_failed_at < ^cutoff))
  end

  defp prune_history() do
    cutoff = DateTime.add(DateTime.utc_now(), -@history_retention_seconds, :second)

    Repo.delete_all(
      from(j in Job, where: j.state in ["done", "failed"] and j.finished_at < ^cutoff)
    )
  end

  defp schedule_tick() do
    Process.send_after(self(), :tick, @interval_seconds * 1000)
  end
end
