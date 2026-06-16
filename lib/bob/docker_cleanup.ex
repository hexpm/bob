defmodule Bob.DockerCleanup do
  @moduledoc """
  Prunes Docker Hub tags Bob no longer needs to keep.

  Per-arch repos (build staging) drop tags built more than 30 days ago; manifest
  repos drop tags not pulled in 180 days (falling back to `built_at` when a tag
  has no recorded pull). Tags pinned by a build request reservation are always
  kept — see `Bob.BuildRequests`.

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

  defp configured_mode(), do: Application.get_env(:bob, :docker_cleanup_mode, :dry_run)

  defp dry_run() do
    per_arch = Artifacts.count_stale_per_arch_tags(per_arch_cutoff())
    manifest = Artifacts.count_stale_manifest_tags(manifest_cutoff())

    Logger.info(
      "DOCKER CLEANUP dry-run: per-arch built_at < #{@per_arch_max_age_days}d -> " <>
        "#{format_counts(per_arch)}; manifest last_pulled < #{@manifest_unpulled_days}d -> " <>
        "#{format_counts(manifest)}"
    )

    {:dry_run, %{per_arch: per_arch, manifest: manifest}}
  end

  defp live(opts) do
    deleter = Keyword.get(opts, :deleter, &Bob.DockerHub.delete_tag/2)
    limit = Keyword.get(opts, :limit, configured_batch())

    candidates =
      Artifacts.stale_per_arch_tags(per_arch_cutoff(), limit) ++
        Artifacts.stale_manifest_tags(manifest_cutoff(), limit)

    deleted = delete(candidates, deleter)
    Logger.info("DOCKER CLEANUP deleted #{deleted}/#{length(candidates)} tag(s)")
    {:live, deleted}
  end

  # Each tag is removed from docker_tags only once Docker Hub confirms deletion,
  # so a tag that errors is left in place and reappears as a candidate next run.
  defp delete(candidates, deleter) do
    deleted =
      Enum.filter(candidates, fn {repo, tag} ->
        case deleter.(repo, tag) do
          :ok ->
            true

          {:error, reason} ->
            Logger.error("DOCKER CLEANUP failed to delete #{repo}:#{tag}: #{inspect(reason)}")
            false
        end
      end)

    Artifacts.delete_docker_tags(deleted)
    length(deleted)
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
