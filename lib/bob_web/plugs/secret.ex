defmodule BobWeb.Plugs.Secret do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
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
