defmodule BobWeb.ArtifactController do
  use BobWeb, :controller

  def add(conn, params) do
    Bob.Artifacts.add(%{
      kind: params["kind"],
      arch: params["arch"],
      os: params["os"],
      name: params["name"],
      ref: params["ref"],
      sha256: params["sha256"],
      built_at: params["date"]
    })

    send_resp(conn, 204, "")
  end

  def add_docker(conn, params) do
    Bob.Artifacts.add_docker_tag(params.repo, params.tag, params.archs)
    send_resp(conn, 204, "")
  end
end
