defmodule Bob.DockerCleanup do
  @moduledoc """
  Deletes per-arch Docker Hub tags older than 30 days. Tags reserved by a build
  request are kept. The manifest repos are not pruned.

  A live run keeps taking batches until one deletes nothing, so it clears the
  whole backlog rather than a single batch. What bounds it is the job's timeout.
  `:docker_cleanup_mode` gates whether it deletes or only reports.
  """

  require Logger

  alias Bob.Artifacts

  # Must stay >= Bob.Job.DockerChecker.build_freshness_days/0 or cleanup deletes
  # tags the checker still expects. Asserted in docker_cleanup_test.
  @per_arch_max_age_days 30

  # Candidate query page size, not a cap on the run.
  @default_batch 10_000

  # Rows are committed per chunk so a killed run keeps its progress.
  @delete_chunk 100

  # Abort a run whose deletes are all failing, e.g. a token without permission.
  @dead_chunk_ceiling 3

  # The rate limiter caps throughput; this only keeps latency from binding it.
  @default_concurrency 25

  def run(opts \\ []) do
    case Keyword.get(opts, :mode, configured_mode()) do
      :dry_run -> dry_run()
      :live -> live(opts)
    end
  end

  defp configured_mode(), do: Application.get_env(:bob, :docker_cleanup_mode, :dry_run)

  defp dry_run() do
    per_arch = Artifacts.count_stale_per_arch_tags(per_arch_cutoff())
    backlog = per_arch |> Map.values() |> Enum.sum()

    # Report both: the backlog is every candidate, a run stops at the batch.
    Logger.info(
      "DOCKER CLEANUP dry-run: per-arch built_at < #{@per_arch_max_age_days}d -> " <>
        "#{format_counts(per_arch)}; one scheduled run would delete " <>
        "#{min(backlog, @default_batch)} of them (batch #{@default_batch})"
    )

    {:dry_run, %{per_arch: per_arch}}
  end

  defp live(opts) do
    deleter = Keyword.get(opts, :deleter, &Bob.DockerHub.delete_tag/2)
    limit = Keyword.get(opts, :limit, @default_batch)
    cutoff = per_arch_cutoff()

    deleted =
      Stream.repeatedly(fn ->
        cutoff
        |> Artifacts.stale_per_arch_tags(limit)
        |> delete(deleter, cutoff)
      end)
      |> Enum.reduce_while(0, fn batch, total ->
        if batch == 0, do: {:halt, total}, else: {:cont, total + batch}
      end)

    Logger.info("DOCKER CLEANUP deleted #{deleted} tag(s)")
    {:live, deleted}
  end

  # Deleted rows are dropped only after Docker Hub confirms, so a failed tag is
  # retried next run. Candidates are re-checked per chunk because a run is slow
  # enough for a tag to get reserved or re-pushed while it works.
  defp delete(candidates, deleter, cutoff) do
    candidates
    |> Enum.chunk_every(@delete_chunk)
    |> Enum.reduce_while({0, 0}, fn chunk, {deleted, dead_chunks} ->
      {confirmed, failed} = delete_chunk(chunk, deleter, cutoff)
      Artifacts.delete_docker_tags(confirmed)
      deleted = deleted + length(confirmed)

      # Whole failed chunks, not individual errors: concurrent deletes have no
      # "consecutive", and a flaky tag shouldn't trip the abort.
      dead_chunks = if failed > 0 and confirmed == [], do: dead_chunks + 1, else: 0

      if dead_chunks >= @dead_chunk_ceiling do
        Logger.error(
          "DOCKER CLEANUP aborting after #{dead_chunks} chunks with no successful delete, " <>
            "deleted #{deleted} tag(s) so far"
        )

        {:halt, {deleted, dead_chunks}}
      else
        {:cont, {deleted, dead_chunks}}
      end
    end)
    |> elem(0)
  end

  defp delete_chunk(chunk, deleter, cutoff) do
    chunk
    |> Artifacts.deletable_docker_tags(cutoff)
    |> Task.async_stream(
      fn {repo, tag} ->
        case deleter.(repo, tag) do
          :ok ->
            {:ok, {repo, tag}}

          {:error, reason} ->
            Logger.error("DOCKER CLEANUP failed to delete #{repo}:#{tag}: #{inspect(reason)}")
            :error
        end
      end,
      max_concurrency: @default_concurrency,
      ordered: false,
      # The limiter can park a caller until its window resets.
      timeout: :infinity
    )
    |> Enum.reduce({[], 0}, fn
      {:ok, {:ok, repo_tag}}, {confirmed, failed} -> {[repo_tag | confirmed], failed}
      {:ok, :error}, {confirmed, failed} -> {confirmed, failed + 1}
    end)
  end

  defp per_arch_cutoff(), do: DateTime.add(DateTime.utc_now(), -@per_arch_max_age_days, :day)

  defp format_counts(counts) do
    total = counts |> Map.values() |> Enum.sum()

    detail =
      counts |> Enum.sort() |> Enum.map_join(", ", fn {repo, count} -> "#{repo}=#{count}" end)

    "#{total} (#{detail})"
  end
end
