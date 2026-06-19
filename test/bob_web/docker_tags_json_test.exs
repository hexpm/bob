defmodule BobWeb.DockerTagsJsonTest do
  use BobWeb.ConnCase

  setup %{conn: conn} do
    Bob.Artifacts.add_docker_tag("hexpm/erlang", "27.0-ubuntu-noble-20250101", [
      "amd64",
      "arm64"
    ])

    Bob.Artifacts.add_docker_tag(
      "hexpm/elixir",
      "1.18.0-erlang-27.0-ubuntu-noble-20250101",
      ["amd64", "arm64"]
    )

    Bob.Artifacts.add_docker_tag(
      "hexpm/elixir",
      "1.17.3-erlang-26.2-debian-bookworm-20250113-slim",
      ["amd64"]
    )

    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  test "returns all tags as JSON", %{conn: conn} do
    body = conn |> get(~p"/docker") |> json_response(200)

    assert body["total"] == 3
    assert body["offset"] == 0
    assert body["page_size"] == 100

    tags = Enum.map(body["tags"], & &1["tag"])
    assert "27.0-ubuntu-noble-20250101" in tags
    assert "1.18.0-erlang-27.0-ubuntu-noble-20250101" in tags
    assert "1.17.3-erlang-26.2-debian-bookworm-20250113-slim" in tags

    tag = Enum.find(body["tags"], &(&1["tag"] == "27.0-ubuntu-noble-20250101"))
    assert tag["repo"] == "hexpm/erlang"
    assert tag["archs"] == ["amd64", "arm64"]
    assert tag["built_at"] =~ ~r/^\d{4}-\d{2}-\d{2}T/
  end

  test "filters by tag prefix like the LiveView", %{conn: conn} do
    body = conn |> get(~p"/docker?tag=1.18") |> json_response(200)

    assert body["total"] == 1
    assert Enum.map(body["tags"], & &1["tag"]) == ["1.18.0-erlang-27.0-ubuntu-noble-20250101"]
  end

  test "filters by structured params", %{conn: conn} do
    body =
      conn
      |> get(~p"/docker?repo=hexpm/elixir&os=ubuntu&erlang_version=27")
      |> json_response(200)

    assert Enum.map(body["tags"], & &1["tag"]) == ["1.18.0-erlang-27.0-ubuntu-noble-20250101"]
  end

  test "a tag prefix drops the structured filters, matching the form", %{conn: conn} do
    body =
      conn
      |> get(~p"/docker?tag=1&erlang_version=26&os=debian")
      |> json_response(200)

    assert body["total"] == 2
  end

  test "browsers still get the LiveView HTML", %{conn: conn} do
    conn = conn |> delete_req_header("accept") |> get(~p"/docker")
    assert html_response(conn, 200) =~ "Docker tags"
  end
end
