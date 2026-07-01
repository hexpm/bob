defmodule Bob.DockerCleanup do
  @moduledoc """
  Prunes Docker Hub tags Bob no longer needs to keep.

  Per-arch repos (build staging) drop tags built more than 30 days ago; manifest
  repos drop tags neither pulled nor built in 180 days. Tags pinned by a build
  request reservation are always kept — see `Bob.BuildRequests`.

  `run/1` honours `:docker_cleanup_mode` (`:dry_run` by default, or `:live`). A
  dry run logs and returns the counts a live run would delete without touching
  Docker Hub; a live run deletes a bounded batch, paced by the shared rate
  limiter, and converges over successive daily runs.
  """

  require Logger

  alias Bob.Artifacts

  @per_arch_max_age_days 30
  @manifest_unpulled_days 180
  @default_batch 100_000

  def run(opts \\ []) do
    case Keyword.get(opts, :mode, configured_mode()) do
      :dry_run -> dry_run()
      :live -> live(opts)
    end
  end

  def per_arch_max_age_days(), do: @per_arch_max_age_days
  def manifest_unpulled_days(), do: @manifest_unpulled_days

  @doc """
  When a tag becomes eligible for removal, or `nil` for a repo not under cleanup.
  Per-arch tags expire a fixed number of days after they were built; manifest
  tags that many days after their last pull or build, whichever is later.
  Mirrors the cleanup's own rule so the UI and the deleter never disagree.
  """
  def removal_at(repo, built_at, last_pulled) do
    cond do
      repo in Artifacts.docker_cleanup_per_arch_repos() ->
        DateTime.add(built_at, @per_arch_max_age_days, :day)

      repo in Artifacts.docker_cleanup_manifest_repos() ->
        last_activity = Enum.max([built_at | List.wrap(last_pulled)], DateTime)
        DateTime.add(last_activity, @manifest_unpulled_days, :day)

      true ->
        nil
    end
  end

  defp configured_mode(), do: Application.get_env(:bob, :docker_cleanup_mode, :dry_run)

  defp dry_run() do
    per_arch = Artifacts.count_stale_per_arch_tags(per_arch_cutoff())
    manifest = Artifacts.count_stale_manifest_tags(manifest_cutoff())

    Logger.info(
      "DOCKER CLEANUP dry-run: per-arch built_at < #{@per_arch_max_age_days}d -> " <>
        "#{format_counts(per_arch)}; manifest pulled/built < #{@manifest_unpulled_days}d -> " <>
        "#{format_counts(manifest)}"
    )

    {:dry_run, %{per_arch: per_arch, manifest: manifest}}
  end

  defp live(opts) do
    deleter = Keyword.get(opts, :deleter, &Bob.DockerHub.delete_tag/2)
    limit = Keyword.get(opts, :limit, configured_batch())

    # `limit` budgets the whole run — per-arch candidates first, the remainder
    # for manifests — so backlog in both groups can't double a day's
    # rate-limited deletes.
    per_arch = Artifacts.stale_per_arch_tags(per_arch_cutoff(), limit)
    candidates = per_arch ++ stale_manifest_tags(limit - length(per_arch))

    deleted = delete(candidates, deleter)
    Logger.info("DOCKER CLEANUP deleted #{deleted}/#{length(candidates)} tag(s)")
    {:live, deleted}
  end

  defp stale_manifest_tags(limit) when limit <= 0, do: []
  defp stale_manifest_tags(limit), do: Artifacts.stale_manifest_tags(manifest_cutoff(), limit)

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
  defp manifest_cutoff(), do: DateTime.add(DateTime.utc_now(), -@manifest_unpulled_days, :day)

  defp configured_batch(), do: Application.get_env(:bob, :docker_cleanup_batch, @default_batch)

  defp format_counts(counts) do
    total = counts |> Map.values() |> Enum.sum()

    detail =
      counts |> Enum.sort() |> Enum.map_join(", ", fn {repo, count} -> "#{repo}=#{count}" end)

    "#{total} (#{detail})"
  end
end
