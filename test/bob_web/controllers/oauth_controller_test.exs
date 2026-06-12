defmodule BobWeb.OAuthControllerTest do
  use BobWeb.ConnCase

  setup do
    Bob.FakeHexpm.reset()
    :ok
  end

  @tokens %{
    "access_token" => "eyJ.access",
    "refresh_token" => "eyJ.refresh",
    "expires_in" => 1800
  }

  describe "GET /oauth/login" do
    test "redirects to the hexpm authorize url and stores the flow in the session", %{conn: conn} do
      conn = get(conn, ~p"/oauth/login")

      location = redirected_to(conn, 302)
      assert location =~ "http://localhost:4000/oauth/authorize?"

      query = URI.decode_query(URI.parse(location).query)
      assert query["response_type"] == "code"
      assert query["scope"] == "api:read"
      assert query["code_challenge_method"] == "S256"
      assert query["redirect_uri"] == "http://localhost:4002/oauth/callback"

      assert get_session(conn, "oauth_state") == query["state"]
      assert get_session(conn, "oauth_code_verifier")
      assert get_session(conn, "oauth_return_to") == "/"
    end

    test "stores the sanitized return path", %{conn: conn} do
      conn = get(conn, ~p"/oauth/login?return_to=/request")
      assert get_session(conn, "oauth_return_to") == "/request"

      conn = get(conn, ~p"/oauth/login?return_to=//evil.com")
      assert get_session(conn, "oauth_return_to") == "/"
    end

    test "redirects straight to the return path when already logged in", %{conn: conn} do
      conn =
        conn
        |> init_test_session(session_fixture())
        |> get(~p"/oauth/login?return_to=/request")

      assert redirected_to(conn, 302) == "/request"
    end
  end

  describe "GET /oauth/callback" do
    test "logs the user in and redirects to the stored return path", %{conn: conn} do
      Bob.FakeHexpm.stub(:exchange_code, {:ok, @tokens})
      Bob.FakeHexpm.stub(:get_current_user, {:ok, %{"username" => "eric"}})

      conn =
        conn
        |> init_test_session(%{
          "oauth_state" => "state123",
          "oauth_code_verifier" => "verifier",
          "oauth_return_to" => "/request"
        })
        |> get(~p"/oauth/callback?code=code123&state=state123")

      assert redirected_to(conn, 302) == "/request"
      assert get_session(conn, "current_user") == %{"username" => "eric"}
      assert get_session(conn, "access_token") == "eyJ.access"
      assert get_session(conn, "refresh_token") == "eyJ.refresh"
      assert get_session(conn, "token_expires_at")
      refute get_session(conn, "oauth_state")
      refute get_session(conn, "oauth_code_verifier")
      refute get_session(conn, "oauth_return_to")
    end

    test "rejects a state mismatch", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{"oauth_state" => "expected", "oauth_code_verifier" => "verifier"})
        |> get(~p"/oauth/callback?code=code123&state=wrong")

      assert redirected_to(conn, 302) == "/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "invalid OAuth state"
      refute get_session(conn, "current_user")
    end

    test "rejects a missing state", %{conn: conn} do
      conn = get(conn, ~p"/oauth/callback?code=code123")

      assert redirected_to(conn, 302) == "/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "invalid OAuth state"
    end

    test "surfaces errors returned by hexpm", %{conn: conn} do
      conn = get(conn, ~p"/oauth/callback?error=access_denied")

      assert redirected_to(conn, 302) == "/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "access_denied"
    end

    test "rejects a missing code", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{"oauth_state" => "state123", "oauth_code_verifier" => "verifier"})
        |> get(~p"/oauth/callback?state=state123")

      assert redirected_to(conn, 302) == "/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "missing OAuth code"
    end

    test "shows an error when the code exchange fails", %{conn: conn} do
      Bob.FakeHexpm.stub(:exchange_code, {:error, {400, "invalid_grant"}})

      conn =
        init_test_session(conn, %{
          "oauth_state" => "state123",
          "oauth_code_verifier" => "verifier"
        })

      {conn, log} =
        ExUnit.CaptureLog.with_log(fn ->
          get(conn, ~p"/oauth/callback?code=code123&state=state123")
        end)

      assert log =~ "code exchange failed"
      assert redirected_to(conn, 302) == "/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "logging in to hex.pm failed"
      refute get_session(conn, "current_user")
      refute get_session(conn, "access_token")
    end
  end

  describe "POST /oauth/logout" do
    test "drops the session and redirects home", %{conn: conn} do
      Bob.FakeHexpm.stub(:revoke_token, :ok)

      conn =
        conn
        |> init_test_session(session_fixture())
        |> post(~p"/oauth/logout")

      assert redirected_to(conn, 302) == "/"
      assert conn.private.plug_session_info == :drop
      assert conn.assigns.current_user == nil
    end
  end

  defp session_fixture() do
    %{
      "current_user" => %{"username" => "eric"},
      "access_token" => "eyJ.access",
      "refresh_token" => "eyJ.refresh",
      "token_expires_at" => System.system_time(:second) + 1800
    }
  end
end
