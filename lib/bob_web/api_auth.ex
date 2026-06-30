defmodule BobWeb.ApiAuth do
  import Plug.Conn

  def require_api_auth(conn, _opts) do
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
