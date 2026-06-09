defmodule BobWeb.Plugs.Secret do
  import Plug.Conn

  def init(opts), do: opts

  def call(%{path_info: ["api" | _]} = conn, _opts) do
    authenticate(conn)
  end

  def call(conn, opts) when is_list(opts) do
    if Keyword.get(opts, :api_only, false) do
      conn
    else
      authenticate(conn)
    end
  end

  defp authenticate(conn) do
    secret = Application.get_env(:bob, :agent_secret)

    if authorized?(get_req_header(conn, "authorization"), secret) do
      conn
    else
      conn
      |> send_resp(401, "")
      |> halt()
    end
  end

  defp authorized?([authorization], secret)
       when is_binary(authorization) and is_binary(secret) and byte_size(secret) > 0 and
              byte_size(authorization) == byte_size(secret) do
    Plug.Crypto.secure_compare(authorization, secret)
  end

  defp authorized?(_headers, _secret), do: false
end
