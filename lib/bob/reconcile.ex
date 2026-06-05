defmodule Bob.Reconcile do
  @moduledoc """
  Seeds and reconciles the Docker tag and base-image caches.

  `backfill/1` is run once at cutover (`Bob.Release.backfill/0`); `reconcile/1`
  runs nightly via `Bob.Job.Reconcile`. Both page Docker Hub through an injected
  fetcher (default `Bob.DockerHub.fetch_repo_tags/1`) and write through
  `Bob.Artifacts`. A repo whose fetch returns an empty list is skipped, so a
  transient Docker Hub failure never wipes its rows.
  """

  require Logger

  @archs ["amd64", "arm64"]
  @linuxes ["ubuntu-22.04", "ubuntu-24.04", "ubuntu-26.04"]

  @per_arch_repos [
    {"hexpm/erlang-amd64", "amd64"},
    {"hexpm/erlang-arm64", "arm64"},
    {"hexpm/elixir-amd64", "amd64"},
    {"hexpm/elixir-arm64", "arm64"}
  ]
  @manifest_repos ["hexpm/erlang", "hexpm/elixir"]
  @base_repos ["library/alpine", "library/ubuntu", "library/debian"]

  def reconcile(fetch \\ &Bob.DockerHub.fetch_repo_tags/1) do
    sync_per_arch_repos(fetch)
    sync_manifest_repos(fetch)
    sync_base_repos(fetch)
    :ok
  end

  def backfill(fetch \\ &Bob.DockerHub.fetch_repo_tags/1) do
    reconcile(fetch)
    import_otp_builds()
    :ok
  end

  defp sync_per_arch_repos(fetch) do
    Enum.each(@per_arch_repos, fn {repo, arch} ->
      case fetch.(repo) do
        [] ->
          Logger.warning("RECONCILE empty fetch for #{repo}, skipping")

        tags ->
          Bob.Artifacts.replace_docker_tags(
            repo,
            Enum.map(tags, fn {tag, _archs} -> {tag, [arch]} end)
          )
      end
    end)
  end

  defp sync_manifest_repos(fetch) do
    Enum.each(@manifest_repos, fn repo ->
      case fetch.(repo) do
        [] ->
          Logger.warning("RECONCILE empty fetch for #{repo}, skipping")

        tags ->
          Bob.Artifacts.replace_docker_tags(
            repo,
            Enum.map(tags, fn {tag, archs} -> {tag, known_archs(archs)} end)
          )
      end
    end)
  end

  defp sync_base_repos(fetch) do
    Enum.each(@base_repos, fn repo ->
      case fetch.(repo) do
        [] ->
          Logger.warning("RECONCILE empty fetch for #{repo}, skipping")

        tags ->
          multi_arch =
            tags
            |> Enum.filter(fn {_tag, archs} -> Enum.all?(@archs, &(&1 in archs)) end)
            |> Enum.map(fn {tag, _archs} -> tag end)

          Bob.Artifacts.replace_base_image_tags(repo, multi_arch)
      end
    end)
  end

  defp known_archs(archs) do
    archs
    |> Enum.filter(&(&1 in @archs))
    |> Enum.sort()
  end

  defp import_otp_builds() do
    for arch <- @archs, os <- @linuxes do
      case Bob.Store.fetch_text("builds/otp/#{arch}/#{os}/builds.txt") do
        nil ->
          :skip

        body ->
          body
          |> String.split("\n", trim: true)
          |> Enum.each(&import_builds_line(&1, arch, os))
      end
    end

    :ok
  end

  defp import_builds_line(line, arch, os) do
    case String.split(line, " ", trim: true) do
      [name, ref, date, sha256] ->
        Bob.Artifacts.upsert(%{
          kind: "otp",
          arch: arch,
          os: os,
          name: name,
          ref: ref,
          sha256: sha256,
          built_at: date
        })

      _other ->
        Logger.warning("BACKFILL skipping malformed builds.txt line: #{inspect(line)}")
    end
  end
end
