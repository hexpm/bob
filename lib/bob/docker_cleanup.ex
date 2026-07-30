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
  limiter, and converges over successive daily runs.
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

  # Sized so a full batch finishes well inside `Bob.Runner`'s three-hour job
  # timeout: deletes are serial and paced at Docker Hub's 600 requests/minute,
  # so this is roughly 20 minutes of pacing plus per-tag overhead. A backlog
  # larger than this drains over successive nights.
  @default_batch 10_000

  # Rows are dropped in chunks as the batch progresses rather than once at the
  # end. A run that is killed mid-batch — the three-hour timeout, a rolling
  # deploy, an OOM — must not leave `docker_tags` claiming tags that are already
  # gone from Docker Hub, or the next run re-issues the same deletes, pays the
  # rate limit for a batch of 404s, and makes no progress either.
  @delete_chunk 100

  # A run where every delete fails is a misconfiguration, not a backlog: a token
  # without delete permission returns 401 for all 10,000 candidates. Without a
  # ceiling that is hours of full-rate Docker Hub traffic and 10,000 error lines,
  # repeated nightly.
  @error_ceiling 25

  def run(opts \\ []) do
    case Keyword.get(opts, :mode, configured_mode()) do
      :dry_run -> dry_run()
      :live -> live(opts)
    end
  end

  def per_arch_max_age_days(), do: @per_arch_max_age_days

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
    batch = configured_batch()

    # The backlog is the whole candidate set; a live run stops at the batch
    # limit. Reporting only the backlog would overstate one night's deletions by
    # orders of magnitude, and that is the number read before flipping to :live.
    Logger.info(
      "DOCKER CLEANUP dry-run: per-arch built_at < #{@per_arch_max_age_days}d -> " <>
        "#{format_counts(per_arch)}; a live run would delete #{min(backlog, batch)} of them " <>
        "tonight (batch #{batch})"
    )

    {:dry_run, %{per_arch: per_arch, backlog: backlog, next_run: min(backlog, batch)}}
  end

  defp live(opts) do
    deleter = Keyword.get(opts, :deleter, &Bob.DockerHub.delete_tag/2)
    limit = Keyword.get(opts, :limit, configured_batch())
    chunk = Keyword.get(opts, :chunk, @delete_chunk)
    cutoff = per_arch_cutoff()

    # `limit` bounds a single run's deletes so a large backlog is spread over
    # successive days rather than spending hours of the rate limiter at once.
    candidates = Artifacts.stale_per_arch_tags(cutoff, limit)

    deleted = delete(candidates, deleter, cutoff, chunk)
    Logger.info("DOCKER CLEANUP deleted #{deleted}/#{length(candidates)} tag(s)")
    {:live, deleted}
  end

  # Each tag is removed from docker_tags only once Docker Hub confirms deletion,
  # so a tag that errors is left in place and reappears as a candidate next run.
  # Candidates are re-checked per tag rather than trusted from selection time:
  # the rate-limited batch can run for hours, and in that window a request can
  # pin a tag or a re-push can make it fresh again. Both must be honoured, or
  # the run deletes an image someone just asked for or just pushed.
  defp delete(candidates, deleter, cutoff, chunk) do
    candidates
    |> Enum.chunk_every(chunk)
    |> Enum.reduce_while({0, 0}, fn chunk, {deleted, consecutive_errors} ->
      {confirmed, consecutive_errors} = delete_chunk(chunk, deleter, cutoff, consecutive_errors)
      Artifacts.delete_docker_tags(confirmed)
      deleted = deleted + length(confirmed)

      if consecutive_errors >= @error_ceiling do
        Logger.error(
          "DOCKER CLEANUP aborting after #{consecutive_errors} consecutive failures, " <>
            "deleted #{deleted} tag(s) so far"
        )

        {:halt, {deleted, consecutive_errors}}
      else
        {:cont, {deleted, consecutive_errors}}
      end
    end)
    |> elem(0)
  end

  defp delete_chunk(chunk, deleter, cutoff, consecutive_errors) do
    Enum.reduce(chunk, {[], consecutive_errors}, fn {repo, tag}, {confirmed, errors} ->
      cond do
        errors >= @error_ceiling ->
          {confirmed, errors}

        not Artifacts.docker_tag_deletable?(repo, tag, cutoff) ->
          {confirmed, 0}

        true ->
          case deleter.(repo, tag) do
            :ok ->
              {[{repo, tag} | confirmed], 0}

            {:error, reason} ->
              Logger.error("DOCKER CLEANUP failed to delete #{repo}:#{tag}: #{inspect(reason)}")
              {confirmed, errors + 1}
          end
      end
    end)
  end

  defp per_arch_cutoff(), do: DateTime.add(DateTime.utc_now(), -@per_arch_max_age_days, :day)

  # `||` rather than a get_env default: runtime.exs sets the key to nil when
  # BOB_DOCKER_CLEANUP_BATCH is unset or unparseable, and a set-but-nil key
  # would otherwise defeat the default.
  defp configured_batch(),
    do: Application.get_env(:bob, :docker_cleanup_batch) || @default_batch

  defp format_counts(counts) do
    total = counts |> Map.values() |> Enum.sum()

    detail =
      counts |> Enum.sort() |> Enum.map_join(", ", fn {repo, count} -> "#{repo}=#{count}" end)

    "#{total} (#{detail})"
  end
end
