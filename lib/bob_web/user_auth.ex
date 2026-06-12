defmodule BobWeb.UserAuth do
  use BobWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  require Logger

  # Refresh access tokens this close to expiry so they don't expire mid-request.
  @token_refresh_buffer 5 * 60

  def fetch_current_user(conn, _opts) do
    case get_session(conn, "current_user") do
      nil ->
        assign(conn, :current_user, nil)

      user ->
        if token_needs_refresh?(conn) do
          refresh_tokens(conn, user)
        else
          assign(conn, :current_user, user)
        end
    end
  end

  def require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_session("oauth_return_to", current_path(conn))
      |> redirect(to: ~p"/oauth/login")
      |> halt()
    end
  end

  def on_mount(:mount_current_user, _params, session, socket) do
    {:cont, Phoenix.Component.assign(socket, :current_user, session["current_user"])}
  end

  def on_mount(:ensure_authenticated, _params, session, socket) do
    case session["current_user"] do
      nil ->
        {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/oauth/login")}

      user ->
        {:cont, Phoenix.Component.assign(socket, :current_user, user)}
    end
  end

  def log_in_user(conn, user, tokens) do
    conn
    |> configure_session(renew: true)
    |> put_session("current_user", user)
    |> store_tokens(tokens)
    |> assign(:current_user, user)
  end

  def log_out_user(conn) do
    conn
    |> configure_session(drop: true)
    |> assign(:current_user, nil)
  end

  def safe_return_path("/" <> rest = path) do
    if String.starts_with?(rest, "/") do
      "/"
    else
      path
    end
  end

  def safe_return_path(_other), do: "/"

  defp store_tokens(conn, tokens) do
    expires_at = System.system_time(:second) + tokens["expires_in"]
    refresh_token = tokens["refresh_token"] || get_session(conn, "refresh_token")

    conn
    |> put_session("access_token", tokens["access_token"])
    |> put_session("refresh_token", refresh_token)
    |> put_session("token_expires_at", expires_at)
  end

  defp token_needs_refresh?(conn) do
    case get_session(conn, "token_expires_at") do
      nil -> true
      expires_at -> expires_at - System.system_time(:second) <= @token_refresh_buffer
    end
  end

  defp refresh_tokens(conn, user) do
    with refresh_token when is_binary(refresh_token) <- get_session(conn, "refresh_token"),
         {:ok, tokens} <- Bob.Hexpm.refresh_token(refresh_token) do
      conn
      |> store_tokens(tokens)
      |> assign(:current_user, user)
    else
      error ->
        Logger.warning("OAUTH token refresh failed: #{inspect(error)}")

        conn
        |> clear_auth_session()
        |> assign(:current_user, nil)
    end
  end

  defp clear_auth_session(conn) do
    Enum.reduce(
      ["current_user", "access_token", "refresh_token", "token_expires_at"],
      conn,
      &delete_session(&2, &1)
    )
  end
end
