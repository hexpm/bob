defmodule Bob.Router do
  use Plug.Router
  import Plug.Conn

  plug Bob.Plugs.Exception

  plug :match
  plug :dispatch

  match _ do
    send_resp(conn, 404, "ERROR: 404")
  end
end
