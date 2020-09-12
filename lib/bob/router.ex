defmodule Bob.Router do
  use Plug.Router
  use Bob.Plug.Rollbax

  import Plug.Conn

  def call(conn, opts) do
    Bob.Plug.Exception.call(conn, fun: &super(&1, opts))
  end

  plug(Bob.Plug.Forwarded)
  plug(Bob.Plug.Status)
  # TODO: SSL?

  plug Plug.RequestId
  plug Logster.Plugs.Logger, excludes: [:params]

  plug(:secret)

  plug(Plug.Parsers,
    pass: ["application/json", "application/vnd.bob+erlang"],
    parsers: [:json, Bob.Plug.Parser],
    json_decoder: Jason
  )

  plug(:match)
  plug(:dispatch)

  post "queue/start" do
    jobs =
      conn.params.jobs
      |> Bob.RemoteQueue.prioritize()
      |> Bob.RemoteQueue.start_jobs(conn.params.num)

    conn
    |> put_resp_header("content-type", "application/vnd.bob+erlang")
    |> send_resp(200, Bob.Plug.ErlangFormat.encode_to_iodata!(%{jobs: jobs}))
  end

  post "queue/success" do
    Bob.Queue.success(conn.params[:id])
    send_resp(conn, 204, "")
  end

  post "queue/failure" do
    Bob.Queue.failure(conn.params[:id])
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
