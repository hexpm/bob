defmodule Bob.DockerCleanup do
  @moduledoc """
  Prunes `hexpm/elixir-amd64` and `hexpm/elixir-arm64`, which only hold the
  single-arch images the multi-arch manifests are assembled from. A tag built
  more than 30 days ago is removed; the multi-arch image it backs stays
  available. Tags pinned by a build request reservation are always kept — see
  `Bob.BuildRequests`. The erlang per-arch repos are deliberately excluded, for
  the reason recorded on `Bob.Artifacts.docker_cleanup_per_arch_repos/0`.

  The manifest repos (`hexpm/erlang`, `hexpm/elixir`) are not pruned. The only
  signal for "nobody uses this image" would be Docker Hub's `tag_last_pulled`,
  and it does not carry that meaning. Measured 2026-07-29: something walks every
  tag in both repos roughly every 80 days, taking several days to cover
  `hexpm/elixir`, and resets the field as it goes — 99.5% of `hexpm/erlang`'s
  36,117 tags share the single date 2026-07-25, and nothing in that repo is more
  than five days idle. Only 0.33% of `hexpm/elixir` ever crosses 180 days, and
  those are the tags the last crawl happened to miss rather than the unused
  ones. A retention rule on that field would fire close to arbitrarily, with its
  blast radius set by someone else's crawl schedule.

  `run/1` honours `:docker_cleanup_mode` (`:dry_run` by default, or `:live`). A
  dry run logs and returns the counts a live run would delete without touching
  Docker Hub; a live run deletes a bounded batch, paced by the shared rate
  limiter, and converges over successive daily runs. `drain/1` clears the whole
  backlog in one go for the initial cleanup.
  """

  require Logger

  alias Bob.Artifacts

  # Per-arch tags are removed this long after they were built. Must stay >=
  # `Bob.Job.DockerChecker.build_freshness_days/0`: the checker's expected set
  # is filtered on release recency, and a tag is always built after the release
  # that triggered it, so a shorter window here would delete tags the checker
  # still expects and rebuild them on the next pass. `docker_cleanup_test`
  # asserts the inequality.
  @per_arch_max_age_days 30

  # What one scheduled run deletes, sized to finish well inside `Bob.Runner`'s
  # three-hour job timeout at Docker Hub's 600 requests/minute. Steady state is
  # only tens of tags a night, so nothing needs to tune this; the initial
  # backlog is what `drain/1` is for, and it takes `:limit` directly.
  @default_batch 10_000

  # Rows are dropped in chunks as the batch progresses rather than once at the
  # end. A run that is killed mid-batch — the three-hour timeout, a rolling
  # deploy, an OOM — must not leave `docker_tags` claiming tags that are already
  # gone from Docker Hub, or the next run re-issues the same deletes, pays the
  # rate limit for a batch of 404s, and makes no progress either.
  @delete_chunk 100

  # A run where whole chunks fail is a misconfiguration, not a backlog: a token
  # without delete permission returns 401 for every candidate. Without a ceiling
  # that is hours of full-rate Docker Hub traffic and an error line per tag,
  # repeated nightly.
  @dead_chunk_ceiling 3

  # Concurrent deletes in flight. The rate limiter enforces the real ceiling, so
  # this only needs to be high enough that round-trip latency is not the
  # bottleneck. Deliberately below the pool size (10 in prod) is unnecessary —
  # the re-check is one query per chunk, not per tag.
  @default_concurrency 25

  def run(opts \\ []) do
    case Keyword.get(opts, :mode, configured_mode()) do
      :dry_run -> dry_run()
      :live -> live(opts)
    end
  end

  def per_arch_max_age_days(), do: @per_arch_max_age_days

  @doc """
  Deletes the whole backlog instead of one night's batch, looping until a pass
  deletes nothing.

  This deletes whatever `:docker_cleanup_mode` says, including `:dry_run` — it
  is an explicit "clear the backlog" command, and looping a dry run would just
  spin. Pass `mode: :dry_run` to `run/1` instead if you wanted a report.

  Not the scheduled path. `Bob.Job.DockerCleanup` runs through `Bob.Runner`,
  which kills any job at three hours, and the initial backlog is far larger than
  three hours of rate-limited deletes. Run this detached from the shell that
  starts it, or it dies with the rpc connection:

      bin/bob rpc 'Task.Supervisor.start_child(Bob.Tasks, fn -> Bob.DockerCleanup.drain() end)'

  Rows are committed per chunk, so a pod restart mid-drain loses at most the
  chunk in flight, and re-running picks up from wherever it stopped. Safe to run
  while the nightly job is also enabled — both re-check each tag before deleting
  and a vanished row is simply not a candidate.

  A pass that deletes nothing ends the drain, so a tag Docker Hub keeps
  rejecting stops the loop rather than spinning on it.
  """
  def drain(opts \\ []) do
    opts = Keyword.put_new(opts, :mode, :live)
    batch = Keyword.get(opts, :limit, @default_batch)

    Stream.repeatedly(fn -> run(Keyword.put(opts, :limit, batch)) end)
    |> Enum.reduce_while(0, fn {:live, deleted}, total ->
      total = total + deleted

      if deleted == 0 do
        Logger.info("DOCKER CLEANUP drain finished, deleted #{total} tag(s)")
        {:halt, total}
      else
        Logger.info("DOCKER CLEANUP drain progress, deleted #{total} tag(s) so far")
        {:cont, total}
      end
    end)
  end

  @doc """
  When a tag becomes eligible for removal, or `nil` for a repo not under
  cleanup — which includes every manifest repo. Mirrors the cleanup's own rule
  so the UI never warns about a removal the deleter will not perform.
  """
  def removal_at(repo, built_at) do
    if repo in Artifacts.docker_cleanup_per_arch_repos() do
      DateTime.add(built_at, @per_arch_max_age_days, :day)
    end
  end

  defp configured_mode(), do: Application.get_env(:bob, :docker_cleanup_mode, :dry_run)

  defp dry_run() do
    per_arch = Artifacts.count_stale_per_arch_tags(per_arch_cutoff())
    backlog = per_arch |> Map.values() |> Enum.sum()

    # The backlog is the whole candidate set; a scheduled run stops at the batch.
    # Reporting only the backlog would overstate one night's deletions by orders
    # of magnitude, and that is the number read before going live.
    Logger.info(
      "DOCKER CLEANUP dry-run: per-arch built_at < #{@per_arch_max_age_days}d -> " <>
        "#{format_counts(per_arch)}; one scheduled run would delete " <>
        "#{min(backlog, @default_batch)} of them (batch #{@default_batch})"
    )

    {:dry_run, %{per_arch: per_arch, backlog: backlog, next_run: min(backlog, @default_batch)}}
  end

  defp live(opts) do
    deleter = Keyword.get(opts, :deleter, &Bob.DockerHub.delete_tag/2)
    limit = Keyword.get(opts, :limit, @default_batch)
    cutoff = per_arch_cutoff()

    delete_opts = [
      cutoff: cutoff,
      chunk: Keyword.get(opts, :chunk, @delete_chunk),
      concurrency: Keyword.get(opts, :concurrency, @default_concurrency)
    ]

    # `limit` bounds a single run's deletes so a large backlog is spread over
    # successive nights rather than spending hours of the rate limiter at once.
    # `Bob.DockerCleanup.drain/1` is the escape hatch when you want it all gone.
    candidates = Artifacts.stale_per_arch_tags(cutoff, limit)

    deleted = delete(candidates, deleter, delete_opts)
    Logger.info("DOCKER CLEANUP deleted #{deleted}/#{length(candidates)} tag(s)")
    {:live, deleted}
  end

  # Each tag is removed from docker_tags only once Docker Hub confirms deletion,
  # so a tag that errors is left in place and reappears as a candidate next run.
  # Candidates are re-checked per tag rather than trusted from selection time:
  # the rate-limited batch can run for hours, and in that window a request can
  # pin a tag or a re-push can make it fresh again. Both must be honoured, or
  # the run deletes an image someone just asked for or just pushed.
  defp delete(candidates, deleter, opts) do
    cutoff = Keyword.fetch!(opts, :cutoff)
    chunk_size = Keyword.fetch!(opts, :chunk)
    concurrency = Keyword.fetch!(opts, :concurrency)

    candidates
    |> Enum.chunk_every(chunk_size)
    |> Enum.reduce_while({0, 0}, fn chunk, {deleted, dead_chunks} ->
      {confirmed, failed} = delete_chunk(chunk, deleter, cutoff, concurrency)
      Artifacts.delete_docker_tags(confirmed)
      deleted = deleted + length(confirmed)

      # A chunk where every attempt failed is the signal, not individual
      # errors: with concurrent deletes "consecutive" has no meaning, and a
      # broken token fails a whole chunk at a time while a flaky tag does not.
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

  # Deletes run concurrently. The shared rate limiter is the real throttle and
  # blocks each caller until the window has budget, so concurrency here only
  # stops the run being bound by round-trip latency — serial deletes spend most
  # of their time waiting and use a fraction of the budget Docker Hub allows.
  defp delete_chunk(chunk, deleter, cutoff, concurrency) do
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
      max_concurrency: concurrency,
      ordered: false,
      # The limiter can park a caller until the window resets, so the only
      # sensible task deadline is the job timeout that already bounds the run.
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
