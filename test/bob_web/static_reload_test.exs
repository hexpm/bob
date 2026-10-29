defmodule BobWeb.StaticReloadTest do
  use BobWeb.ConnCase

  import Phoenix.LiveViewTest

  # The digests here match cache_static_manifest_latest in config/test.exs.
  test "redirects for a full page load when the client's assets are stale", %{conn: conn} do
    conn =
      put_connect_params(conn, %{
        "_track_static" => [
          "http://localhost:4002/assets/app-00000000000000000000000000000000.css",
          "http://localhost:4002/assets/app-00000000000000000000000000000000.js"
        ]
      })

    assert {:error, {:redirect, %{to: "/docker?tag=1.18"}}} = live(conn, ~p"/docker?tag=1.18")
  end

  test "mounts when the client's assets are current", %{conn: conn} do
    conn =
      put_connect_params(conn, %{
        "_track_static" => [
          "http://localhost:4002/assets/app-11111111111111111111111111111111.css",
          "http://localhost:4002/assets/app-22222222222222222222222222222222.js"
        ]
      })

    assert {:ok, _view, _html} = live(conn, ~p"/docker")
  end

  test "mounts when the client does not track statics", %{conn: conn} do
    assert {:ok, _view, _html} = live(conn, ~p"/docker")
  end
end
