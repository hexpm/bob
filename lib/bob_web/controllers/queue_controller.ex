defmodule BobWeb.QueueController do
  use BobWeb, :controller

  def start(conn, params) do
    jobs =
      params.jobs
      |> Bob.RemoteQueue.prioritize()
      |> Bob.RemoteQueue.start_jobs(params.max_weight, params.weights)

    conn
    |> put_resp_header("content-type", "application/vnd.bob+erlang")
    |> send_resp(200, Bob.Plug.ErlangFormat.encode_to_iodata!(%{jobs: jobs}))
  end

  def success(conn, params) do
    Bob.Queue.success(params.id)
    send_resp(conn, 204, "")
  end

  def failure(conn, params) do
    Bob.Queue.failure(params.id)
    send_resp(conn, 204, "")
  end

  def requeue(conn, params) do
    Bob.Queue.requeue(params.id)
    send_resp(conn, 204, "")
  end

  def add(conn, params) do
    Bob.Queue.add(params.module, params.args)
    send_resp(conn, 204, "")
  end
end
