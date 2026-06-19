defmodule BobWeb.Plugs.SearchJson do
  @moduledoc """
  Serves the artifact and Docker tag search LiveViews as JSON for API clients
  that send `Accept: application/json`, mirroring the LiveView for the same
  query parameters. Other requests, and any other path, fall through untouched
  to the regular browser pipeline and the LiveView.

  This runs ahead of the `:accepts` plug so a JSON request is answered and
  halted before that plug would reject it as not HTML.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias Bob.Artifacts
  alias Bob.Artifacts.{ArtifactSearch, DockerTagSearch}

  def init(opts), do: opts

  def call(conn, _opts) do
    case conn.request_path do
      "/artifacts" -> maybe_json(conn, &artifacts/1)
      "/docker" -> maybe_json(conn, &docker_tags/1)
      _other -> conn
    end
  end

  defp maybe_json(conn, build) do
    if json_requested?(conn) do
      body = build.(fetch_query_params(conn).query_params)
      conn |> json(body) |> halt()
    else
      conn
    end
  end

  defp artifacts(params) do
    offset = ArtifactSearch.parse_offset(params)
    filters = ArtifactSearch.parse_filters(params)
    page = Artifacts.artifact_page(filters, ArtifactSearch.page_size(), offset)

    envelope(page, :artifacts, offset, ArtifactSearch.page_size(), &artifact/1)
  end

  defp docker_tags(params) do
    offset = DockerTagSearch.parse_offset(params)
    filters = DockerTagSearch.parse_filters(params)
    page = Artifacts.docker_tag_page(filters, DockerTagSearch.page_size(), offset)

    envelope(page, :tags, offset, DockerTagSearch.page_size(), &docker_tag/1)
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

  defp json_requested?(conn) do
    conn
    |> get_req_header("accept")
    |> Enum.any?(&String.contains?(&1, "application/json"))
  end
end
