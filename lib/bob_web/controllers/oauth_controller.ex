defmodule BobWeb.OAuthController do
  use BobWeb, :controller

  import BobWeb.UserAuth, only: [safe_return_path: 1, log_in_user: 3, log_out_user: 1]

  require Logger

  def login(conn, params) do
    return_to =
      safe_return_path(params["return_to"] || get_session(conn, "oauth_return_to") || "/")

    if conn.assigns[:current_user] do
      redirect(conn, to: return_to)
    else
      code_verifier = Bob.OAuth.generate_code_verifier()
      state = Bob.OAuth.generate_state()

      authorization_url =
        Bob.OAuth.authorization_url(
          state: state,
          code_challenge: Bob.OAuth.generate_code_challenge(code_verifier),
          redirect_uri: url(~p"/oauth/callback")
        )

      conn
      |> put_session("oauth_state", state)
      |> put_session("oauth_code_verifier", code_verifier)
      |> put_session("oauth_return_to", return_to)
      |> redirect(external: authorization_url)
    end
  end

  def callback(conn, params) do
    cond do
      error = params["error"] ->
        auth_error(conn, params["error_description"] || error)

      params["state"] == nil or params["state"] != get_session(conn, "oauth_state") ->
        auth_error(conn, "invalid OAuth state")

      params["code"] == nil ->
        auth_error(conn, "missing OAuth code")

      true ->
        exchange_code(conn, params["code"])
    end
  end

  def logout(conn, _params) do
    if refresh_token = get_session(conn, "refresh_token") do
      case Bob.Hexpm.revoke_token(refresh_token) do
        :ok -> :ok
        {:error, reason} -> Logger.warning("OAUTH token revocation failed: #{inspect(reason)}")
      end
    end

    conn
    |> log_out_user()
    |> redirect(to: ~p"/")
  end

  defp exchange_code(conn, code) do
    code_verifier = get_session(conn, "oauth_code_verifier")
    return_to = safe_return_path(get_session(conn, "oauth_return_to") || "/")

    with {:ok, tokens} <- Bob.Hexpm.exchange_code(code, code_verifier, url(~p"/oauth/callback")),
         {:ok, user} <- Bob.Hexpm.get_current_user(tokens["access_token"]) do
      conn
      |> delete_session("oauth_state")
      |> delete_session("oauth_code_verifier")
      |> delete_session("oauth_return_to")
      |> log_in_user(%{"username" => user["username"]}, tokens)
      |> redirect(to: return_to)
    else
      {:error, reason} ->
        Logger.error("OAUTH code exchange failed: #{inspect(reason)}")
        auth_error(conn, "logging in to hex.pm failed")
    end
  end

  defp auth_error(conn, message) do
    conn
    |> put_flash(:error, "Authentication failed: #{message}")
    |> redirect(to: ~p"/")
  end
end
