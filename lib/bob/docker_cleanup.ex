defmodule Bob.DockerCleanup do
  @moduledoc """
  Prunes the per-architecture Docker Hub repos, which only hold the single-arch
  images the multi-arch manifests are assembled from. A tag built more than 30
  days ago is removed; the multi-arch image it backs stays available. Tags
  pinned by a build request reservation are always kept — see
  `Bob.BuildRequests`.

  The manifest repos (`hexpm/erlang`, `hexpm/elixir`) are not pruned. The only
  signal for "nobody uses this image" would be Docker Hub's `tag_last_pulled`,
  and it does not carry that meaning: something walks every tag in both repos
  every few days and resets it, so 99.5% of `hexpm/erlang` shares a single pull
  date and no tag anywhere reaches even 90 days idle. A retention rule built on
  it would fire on whichever tags that crawl happened to miss, and its blast
  radius would be set by someone else's schedule.

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
  @default_batch 100_000

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

    Logger.info(
      "DOCKER CLEANUP dry-run: per-arch built_at < #{@per_arch_max_age_days}d -> " <>
        format_counts(per_arch)
    )

    {:dry_run, %{per_arch: per_arch}}
  end

  defp live(opts) do
    deleter = Keyword.get(opts, :deleter, &Bob.DockerHub.delete_tag/2)
    limit = Keyword.get(opts, :limit, configured_batch())

    # `limit` bounds a single run's deletes so a large backlog is spread over
    # successive days rather than spending hours of the rate limiter at once.
    candidates = Artifacts.stale_per_arch_tags(per_arch_cutoff(), limit)

    deleted = delete(candidates, deleter)
    Logger.info("DOCKER CLEANUP deleted #{deleted}/#{length(candidates)} tag(s)")
    {:live, deleted}
  end

  # Each tag is removed from docker_tags only once Docker Hub confirms deletion,
  # so a tag that errors is left in place and reappears as a candidate next run.
  # Reservations are re-checked per tag: the rate-limited batch can run for
  # hours after the candidates were selected, and a request made mid-run must
  # still pin its tag.
  defp delete(candidates, deleter) do
    deleted =
      Enum.filter(candidates, fn {repo, tag} ->
        not Artifacts.docker_tag_reserved?(repo, tag) and confirmed_delete?(deleter, repo, tag)
      end)

    Artifacts.delete_docker_tags(deleted)
    length(deleted)
  end

  defp confirmed_delete?(deleter, repo, tag) do
    case deleter.(repo, tag) do
      :ok ->
        true

      {:error, reason} ->
        Logger.error("DOCKER CLEANUP failed to delete #{repo}:#{tag}: #{inspect(reason)}")
        false
    end
  end

  defp per_arch_cutoff(), do: DateTime.add(DateTime.utc_now(), -@per_arch_max_age_days, :day)

  defp configured_batch(), do: Application.get_env(:bob, :docker_cleanup_batch, @default_batch)

  defp format_counts(counts) do
    total = counts |> Map.values() |> Enum.sum()

    detail =
      counts |> Enum.sort() |> Enum.map_join(", ", fn {repo, count} -> "#{repo}=#{count}" end)

    "#{total} (#{detail})"
  end
end
