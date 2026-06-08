defmodule BobWeb.DockerTagsLiveTest do
  use BobWeb.ConnCase

  import Phoenix.LiveViewTest

  setup do
    Bob.Artifacts.add_docker_tag("hexpm/erlang", "27.0-alpine", ["amd64"])
    Bob.Artifacts.add_docker_tag("hexpm/elixir", "1.18.0-alpine", ["amd64", "arm64"])
    :ok
  end

  test "lists tags and filters by tag text", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/docker")
    assert html =~ "27.0-alpine"
    assert html =~ "1.18.0-alpine"

    html = render_change(view, "search", %{"query" => "1.18", "repo" => ""})
    assert html =~ "1.18.0-alpine"
    refute html =~ "27.0-alpine"
  end

  test "filters by repo dropdown", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/docker")
    html = render_change(view, "search", %{"query" => "", "repo" => "hexpm/erlang"})
    assert html =~ "27.0-alpine"
    refute html =~ "1.18.0-alpine"
  end
end
