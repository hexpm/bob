defmodule Bob.Reconcile do
  @moduledoc """
  Seeds and reconciles the Docker tag and base-image caches.

  `backfill/1` is run once at cutover on the running node (e.g.
  `bin/bob rpc "Bob.Reconcile.backfill()"`); `reconcile/1` runs nightly via
  `Bob.Job.Reconcile`. Both page Docker Hub through an injected
  streamer (default `Bob.DockerHub.stream_repo_tags/2`), staging each page into
  `docker_tags_staging` under a per-run token and applying the full set with a
  set-based swap — so the response is never held in memory and no connection is
  held across the fetch. A repo whose fetch returns nothing or fails is skipped,
  so a transient Docker Hub failure never wipes its rows nor aborts the others.

  Each slice can also be reconciled on its own — `reconcile_per_arch_repos/1`,
  `reconcile_manifest_repos/1`, `reconcile_base_images/1`, and
  `import_otp_builds/0` — to re-run just one kind without paging every repo.
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

  def reconcile_per_arch_repos(stream \\ &Bob.DockerHub.stream_repo_tags/2) do
    Artifacts.prune_staging(@staging_orphan_seconds)
    sync_per_arch_repos(stream)
    :ok
  end

  def reconcile_manifest_repos(stream \\ &Bob.DockerHub.stream_repo_tags/2) do
    Artifacts.prune_staging(@staging_orphan_seconds)
    sync_manifest_repos(stream)
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
      if Artifacts.staged_any?(token, repo) do
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

  def import_otp_builds() do
    for arch <- @archs, os <- @linuxes do
      case Bob.Store.fetch_text("builds/otp/#{arch}/#{os}/builds.txt") do
        nil ->
          :skip

        body ->
          body
          |> String.split("\n", trim: true)
          |> Enum.flat_map(&parse_builds_line(&1, arch, os))
          |> Artifacts.import_artifacts()
      end
    end

    :ok
  end

  # Builds written before the checksum column was added carry only
  # `name ref date`; newer ones append the sha256.
  defp parse_builds_line(line, arch, os) do
    case String.split(line, " ", trim: true) do
      [name, ref, date, sha256] -> build_row(line, arch, os, name, ref, date, sha256)
      [name, ref, date] -> build_row(line, arch, os, name, ref, date, nil)
      _other -> skip_malformed(line)
    end
  end

  defp build_row(line, arch, os, name, ref, date, sha256) do
    case DateTime.from_iso8601(date) do
      {:ok, datetime, _offset} ->
        built_at = %{datetime | microsecond: {elem(datetime.microsecond, 0), 6}}

        [
          %{
            kind: "otp",
            arch: arch,
            os: os,
            name: name,
            ref: ref,
            sha256: sha256,
            built_at: built_at
          }
        ]

      {:error, _reason} ->
        skip_malformed(line)
    end
  end

  defp skip_malformed(line) do
    Logger.warning("BACKFILL skipping malformed builds.txt line: #{inspect(line)}")
    []
  end
end
