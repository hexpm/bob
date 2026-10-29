defmodule BobWeb.UserAuthTest do
  use BobWeb.ConnCase

  import ExUnit.CaptureLog

  alias BobWeb.UserAuth

  @user %{"username" => "eric"}

  setup %{conn: conn} do
    Bob.FakeHexpm.reset()

    conn =
      conn
      |> Map.replace!(:secret_key_base, BobWeb.Endpoint.config(:secret_key_base))
      |> init_test_session(%{})

    {:ok, conn: conn}
  end

  describe "fetch_current_user/2" do
    test "assigns nil without a session user", %{conn: conn} do
      conn = UserAuth.fetch_current_user(conn, [])

      assert conn.assigns.current_user == nil
    end

    test "assigns the session user when the token is fresh", %{conn: conn} do
      conn =
        conn
        |> put_session("current_user", @user)
        |> put_session("token_expires_at", System.system_time(:second) + 1800)
        |> UserAuth.fetch_current_user([])

      assert conn.assigns.current_user == @user
    end

    test "refreshes tokens close to expiry", %{conn: conn} do
      Bob.FakeHexpm.stub(
        :refresh_token,
        {:ok,
         %{
           "access_token" => "eyJ.new-access",
           "refresh_token" => "eyJ.new-refresh",
           "expires_in" => 1800
         }}
      )

      conn =
        conn
        |> put_session("current_user", @user)
        |> put_session("refresh_token", "eyJ.old-refresh")
        |> put_session("token_expires_at", System.system_time(:second) + 60)
        |> UserAuth.fetch_current_user([])

      assert conn.assigns.current_user == @user
      assert get_session(conn, "refresh_token") == "eyJ.new-refresh"
      assert get_session(conn, "token_expires_at") > System.system_time(:second) + 1700
      refute get_session(conn, "access_token")
    end

    test "logs the user out when the refresh fails", %{conn: conn} do
      Bob.FakeHexpm.stub(:refresh_token, {:error, {401, "invalid_grant"}})

      conn =
        conn
        |> put_session("current_user", @user)
        |> put_session("refresh_token", "eyJ.old-refresh")
        |> put_session("token_expires_at", System.system_time(:second) - 1)

      {conn, log} = with_log(fn -> UserAuth.fetch_current_user(conn, []) end)

      assert log =~ "token refresh failed"
      assert conn.assigns.current_user == nil
      refute get_session(conn, "current_user")
      refute get_session(conn, "refresh_token")
    end

    test "logs the user out when the token expired without a refresh token", %{conn: conn} do
      conn =
        conn
        |> put_session("current_user", @user)
        |> put_session("token_expires_at", System.system_time(:second) - 1)

      {conn, _log} = with_log(fn -> UserAuth.fetch_current_user(conn, []) end)

      assert conn.assigns.current_user == nil
      refute get_session(conn, "current_user")
    end
  end

  describe "require_authenticated_user/2" do
    test "passes an authenticated conn through", %{conn: conn} do
      conn =
        conn
        |> assign(:current_user, @user)
        |> UserAuth.require_authenticated_user([])

      refute conn.halted
    end

    test "redirects anonymous users to the login page", %{conn: conn} do
      conn =
        %{conn | path_info: ["request"], request_path: "/request"}
        |> Phoenix.Controller.fetch_flash()
        |> UserAuth.require_authenticated_user([])

      assert conn.halted
      assert redirected_to(conn, 302) == "/oauth/login"
      assert get_session(conn, "oauth_return_to") == "/request"
    end
  end

  describe "on_mount/4" do
    test "mount_current_user assigns from the session" do
      assert {:cont, socket} =
               UserAuth.on_mount(
                 :mount_current_user,
                 %{},
                 %{"current_user" => @user},
                 %Phoenix.LiveView.Socket{}
               )

      assert socket.assigns.current_user == @user

      assert {:cont, socket} =
               UserAuth.on_mount(:mount_current_user, %{}, %{}, %Phoenix.LiveView.Socket{})

      assert socket.assigns.current_user == nil
    end

    test "ensure_authenticated halts anonymous sockets" do
      socket = %Phoenix.LiveView.Socket{
        endpoint: BobWeb.Endpoint,
        router: BobWeb.Router
      }

      assert {:halt, socket} = UserAuth.on_mount(:ensure_authenticated, %{}, %{}, socket)
      assert {:redirect, %{to: "/oauth/login"}} = socket.redirected
    end

    test "ensure_authenticated continues authenticated sockets" do
      assert {:cont, socket} =
               UserAuth.on_mount(
                 :ensure_authenticated,
                 %{},
                 %{"current_user" => @user},
                 %Phoenix.LiveView.Socket{}
               )

      assert socket.assigns.current_user == @user
    end
  end

  describe "safe_return_path/1" do
    test "allows normal paths" do
      assert UserAuth.safe_return_path("/request") == "/request"
    end

    test "rejects protocol-relative and external urls" do
      assert UserAuth.safe_return_path("//evil.com") == "/"
      assert UserAuth.safe_return_path("/\\evil.com") == "/"
      assert UserAuth.safe_return_path("https://evil.com") == "/"
      assert UserAuth.safe_return_path(nil) == "/"
    end
  end
end
