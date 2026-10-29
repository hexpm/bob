defmodule BobWeb.ArtifactsLiveTest do
  use BobWeb.ConnCase

  import Phoenix.LiveViewTest

  setup do
    Bob.Artifacts.upsert(%{
      kind: "otp",
      arch: "amd64",
      os: "ubuntu-24.04",
      name: "OTP-27.0",
      ref: "aaa",
      built_at: ~U[2026-01-01 00:00:00Z]
    })

    Bob.Artifacts.upsert(%{
      kind: "otp",
      arch: "arm64",
      os: "ubuntu-22.04",
      name: "OTP-26.2",
      ref: "bbb",
      built_at: ~U[2026-02-01 00:00:00Z]
    })

    :ok
  end

  test "lists artifacts and filters by free-text", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/artifacts")
    assert html =~ "OTP-27.0"
    assert html =~ "OTP-26.2"
    assert html =~ "2 artifacts"
    assert html =~ ~r/Showing\s*<b>1<\/b>\s*-\s*<b>2<\/b>\s*artifacts\s*of\s*2 artifacts/

    html =
      render_change(view, "search", %{"query" => "27.0", "kind" => "", "arch" => "", "os" => ""})

    assert html =~ "OTP-27.0"
    refute html =~ "OTP-26.2"
    assert html =~ "1 artifact"
    assert html =~ ~r/Showing\s*<b>1<\/b>\s*-\s*<b>1<\/b>\s*artifact\s*of\s*1 artifact/
  end

  test "filters by arch dropdown", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/artifacts")

    html =
      render_change(view, "search", %{"query" => "", "kind" => "", "arch" => "arm64", "os" => ""})

    assert html =~ "OTP-26.2"
    refute html =~ "OTP-27.0"
  end

  test "applies filters from URL params on load", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/artifacts?query=27.0")

    assert html =~ "OTP-27.0"
    refute html =~ "OTP-26.2"
  end

  test "searching patches the URL so filters survive a refresh", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/artifacts")

    render_change(view, "search", %{"query" => "27.0", "kind" => "", "arch" => "", "os" => ""})
    assert_patch(view, ~p"/artifacts?query=27.0")
  end
end
