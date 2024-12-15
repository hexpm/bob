defmodule Bob.Router do
  use Plug.Router
  use Sentry.PlugCapture

  import Plug.Conn

  plug(Bob.Plug.Forwarded)
  plug(Bob.Plug.Status)
  # TODO: SSL?

  plug(Plug.RequestId)
  plug(Logster.Plugs.Logger, excludes: [:params])

  plug(:secret)

  plug(Plug.Parsers,
    pass: ["application/json", "application/vnd.bob+erlang"],
    parsers: [:json, Bob.Plug.Parser],
    json_decoder: Jason
  )

  plug(Sentry.PlugContext)
  plug(:match)
  plug(:dispatch)

  post "queue/start" do
    jobs =
      conn.params.jobs
      |> Bob.RemoteQueue.prioritize()
      |> Bob.RemoteQueue.start_jobs(conn.params.max_weight, conn.params.weights)

    conn
    |> put_resp_header("content-type", "application/vnd.bob+erlang")
    |> send_resp(200, Bob.Plug.ErlangFormat.encode_to_iodata!(%{jobs: jobs}))
  end

  post "queue/success" do
    Bob.Queue.success(conn.params.id)
    send_resp(conn, 204, "")
  end

  post "queue/failure" do
    Bob.Queue.failure(conn.params.id)
    send_resp(conn, 204, "")
  end

  post "queue/add" do
    Bob.Queue.add(conn.params.module, conn.params.args)
    send_resp(conn, 204, "")
  end

  post "docker/add" do
    Bob.DockerHub.Cache.add(conn.params.repo, conn.params.tag, conn.params.archs)
    send_resp(conn, 204, "")
  end

  match _ do
    send_resp(conn, 404, "")
  end

  defp secret(conn, _opts) do
    secret = Application.get_env(:bob, :agent_secret)

    if get_req_header(conn, "authorization") == [secret] do
      conn
    else
      conn
      |> send_resp(401, "")
      |> halt()
    end
  end
end
