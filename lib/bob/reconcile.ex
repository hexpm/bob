defmodule Bob.Reconcile do
  @moduledoc """
  Seeds and reconciles the Docker tag and base-image caches.

  `backfill/1` is run once at cutover (`Bob.Release.backfill/0`); `reconcile/1`
  runs nightly via `Bob.Job.Reconcile`. Both page Docker Hub through an injected
  streamer (default `Bob.DockerHub.stream_repo_tags/2`), staging each page into
  `docker_tags_staging` under a per-run token and applying the full set with a
  set-based swap — so the response is never held in memory and no connection is
  held across the fetch. A repo whose fetch returns nothing or fails is skipped,
  so a transient Docker Hub failure never wipes its rows nor aborts the others.
  """

  require Logger

  alias Bob.Artifacts

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

  # Reclaims staging rows orphaned by a crash between staging and the swap. The
  # threshold far exceeds any single sweep, so it never touches an in-flight run.
  @staging_orphan_seconds 6 * 60 * 60

  def reconcile(stream \\ &Bob.DockerHub.stream_repo_tags/2) do
    Artifacts.prune_staging(@staging_orphan_seconds)
    sync_per_arch_repos(stream)
    sync_manifest_repos(stream)
    sync_base_repos(stream)
    :ok
  end

  def backfill(stream \\ &Bob.DockerHub.stream_repo_tags/2) do
    reconcile(stream)
    import_otp_builds()
    :ok
  end

  def reconcile_base_images(stream \\ &Bob.DockerHub.stream_repo_tags/2) do
    Artifacts.prune_staging(@staging_orphan_seconds)
    sync_base_repos(stream)
    :ok
  end

  defp sync_per_arch_repos(stream) do
    Enum.each(@per_arch_repos, fn {repo, arch} ->
      swap_docker_tags(stream, repo, fn page ->
        Enum.map(page, fn {tag, _archs} -> {tag, [arch]} end)
      end)
    end)
  end

  defp sync_manifest_repos(stream) do
    Enum.each(@manifest_repos, fn repo ->
      swap_docker_tags(stream, repo, fn page ->
        Enum.map(page, fn {tag, archs} -> {tag, known_archs(archs)} end)
      end)
    end)
  end

  defp sync_base_repos(stream) do
    Enum.each(@base_repos, fn repo ->
      stage(stream, repo, & &1, fn token ->
        case Artifacts.staged_multi_arch_tags(token, repo, @archs) do
          [] -> Logger.warning("RECONCILE no multi-arch tags for #{repo}, skipping")
          tags -> Artifacts.replace_base_image_tags(repo, tags)
        end
      end)
    end)
  end

  defp swap_docker_tags(stream, repo, transform) do
    stage(stream, repo, transform, fn token ->
      if Artifacts.staged_tag_count(token, repo) > 0 do
        Artifacts.swap_docker_tags(token, repo)
      else
        Logger.warning("RECONCILE empty fetch for #{repo}, skipping")
      end
    end)
  end

  # Streams a repo into staging under a fresh token, runs `apply_fun` on success,
  # and always discards the token. Both a returned `:error` and a crash in the
  # streamer (DockerHub paging or a staging write) skip the repo without aborting
  # the others; the swap never sees a partial fetch.
  defp stage(stream, repo, transform, apply_fun) do
    token = Ecto.UUID.generate()

    result =
      try do
        stream.(repo, fn page -> Artifacts.stage_docker_tags(token, repo, transform.(page)) end)
      rescue
        exception ->
          Logger.error(
            "RECONCILE fetch failed for #{repo}, skipping: #{Exception.message(exception)}"
          )

          :error
      catch
        :exit, reason ->
          Logger.error("RECONCILE fetch crashed for #{repo}, skipping: #{inspect(reason)}")
          :error
      end

    case result do
      :ok -> apply_fun.(token)
      :error -> :ok
    end

    Artifacts.discard_staging(token)
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
        Artifacts.upsert(%{
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
