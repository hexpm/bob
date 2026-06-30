defmodule BobWeb.PublicApiController do
  @moduledoc """
  Public API endpoints.

  Provide search endpoints similar to the artifact and docker search LiveViews.
  """

  use BobWeb, :controller

  alias Bob.Artifacts
  alias Bob.Artifacts.{ArtifactSearch, DockerTagSearch}

  def artifacts(conn, params) do
    offset = ArtifactSearch.parse_offset(params)
    filters = ArtifactSearch.parse_filters(params)
    page = Artifacts.artifact_page(filters, ArtifactSearch.page_size(), offset)

    json(conn, envelope(page, :artifacts, offset, ArtifactSearch.page_size(), &artifact/1))
  end

  def docker_tags(conn, params) do
    offset = DockerTagSearch.parse_offset(params)
    filters = DockerTagSearch.parse_filters(params)
    page = Artifacts.docker_tag_page(filters, DockerTagSearch.page_size(), offset)

    json(conn, envelope(page, :tags, offset, DockerTagSearch.page_size(), &docker_tag/1))
  end

  defp envelope(%{results: results, total: total}, key, offset, page_size, row) do
    %{key => Enum.map(results, row), total: total, offset: offset, page_size: page_size}
  end

  defp artifact(artifact) do
    %{
      kind: artifact.kind,
      arch: artifact.arch,
      os: artifact.os,
      name: artifact.name,
      ref: artifact.ref,
      sha256: artifact.sha256,
      built_at: artifact.built_at && DateTime.to_iso8601(artifact.built_at)
    }
  end

  defp docker_tag(tag) do
    %{
      repo: tag.repo,
      tag: tag.tag,
      archs: tag.archs,
      built_at: tag.built_at && DateTime.to_iso8601(tag.built_at)
    }
  end
end
