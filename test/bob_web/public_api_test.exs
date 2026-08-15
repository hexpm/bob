defmodule BobWeb.PublicApiTest do
  use BobWeb.ConnCase

  describe "/artifacts" do
    setup %{conn: conn} do
      Bob.Artifacts.upsert(%{
        kind: "otp",
        arch: "amd64",
        os: "ubuntu-24.04",
        name: "OTP-27.0",
        ref: "aaa",
        sha256: "deadbeef",
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

      {:ok, conn: put_req_header(conn, "accept", "application/json")}
    end

    test "returns all artifacts as JSON", %{conn: conn} do
      body = conn |> get(~p"/api/artifacts") |> json_response(200)

      assert body["total"] == 2
      assert body["offset"] == 0
      assert body["page_size"] == 100

      names = Enum.map(body["artifacts"], & &1["name"])
      assert "OTP-27.0" in names
      assert "OTP-26.2" in names

      artifact = Enum.find(body["artifacts"], &(&1["name"] == "OTP-27.0"))
      assert artifact["kind"] == "otp"
      assert artifact["arch"] == "amd64"
      assert artifact["os"] == "ubuntu-24.04"
      assert artifact["ref"] == "aaa"
      assert artifact["sha256"] == "deadbeef"
      assert artifact["built_at"] =~ ~r/^2026-01-01T/
    end

    test "filters by free-text query like the LiveView", %{conn: conn} do
      body = conn |> get(~p"/api/artifacts?query=27.0") |> json_response(200)

      assert body["total"] == 1
      assert Enum.map(body["artifacts"], & &1["name"]) == ["OTP-27.0"]
    end

    test "filters by kind, arch and os", %{conn: conn} do
      body = conn |> get(~p"/api/artifacts?arch=arm64") |> json_response(200)

      assert Enum.map(body["artifacts"], & &1["name"]) == ["OTP-26.2"]
    end
  end

  describe "/docker" do
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
      body = conn |> get(~p"/api/docker") |> json_response(200)

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
      body = conn |> get(~p"/api/docker?tag=1.18") |> json_response(200)

      assert body["total"] == 1
      assert Enum.map(body["tags"], & &1["tag"]) == ["1.18.0-erlang-27.0-ubuntu-noble-20250101"]
    end

    test "filters by structured params", %{conn: conn} do
      body =
        conn
        |> get(~p"/api/docker?repo=hexpm/elixir&os=ubuntu&erlang_version=27")
        |> json_response(200)

      assert Enum.map(body["tags"], & &1["tag"]) == ["1.18.0-erlang-27.0-ubuntu-noble-20250101"]
    end

    test "sorts by multiple parsed fields", %{conn: conn} do
      Bob.Artifacts.add_docker_tag(
        "hexpm/elixir",
        "1.20.1-erlang-29.0.2-debian-trixie-20260610-slim",
        ["amd64", "arm64"],
        ~U[2025-01-01 00:00:00Z]
      )

      Bob.Artifacts.add_docker_tag(
        "hexpm/elixir",
        "1.20.1-erlang-30.0-debian-trixie-20260610-slim",
        ["amd64", "arm64"],
        ~U[2025-01-01 00:00:00Z]
      )

      body =
        conn
        |> get("/api/docker?repo=hexpm%2Felixir&sort=elixir_version%2Cerlang_version")
        |> json_response(200)

      assert hd(body["tags"])["tag"] ==
               "1.20.1-erlang-30.0-debian-trixie-20260610-slim"
    end

    test "defaults malformed sort params to build time", %{conn: conn} do
      body = conn |> get("/api/docker?sort[]=os") |> json_response(200)

      assert body["total"] == 3
    end

    test "treats build time as an exclusive sort", %{conn: conn} do
      Bob.Artifacts.add_docker_tag(
        "hexpm/elixir",
        "99.0.0-erlang-99.0-alpine-3.22.0",
        ["amd64", "arm64"],
        ~U[2025-01-01 00:00:00Z]
      )

      Bob.Artifacts.add_docker_tag(
        "hexpm/elixir",
        "1.0.0-erlang-1.0-alpine-3.22.1",
        ["amd64", "arm64"],
        ~U[2026-01-01 00:00:00Z]
      )

      body =
        conn
        |> get("/api/docker?os=alpine&sort=elixir_version%2Cbuilt_at")
        |> json_response(200)

      assert Enum.map(body["tags"], & &1["tag"]) == [
               "1.0.0-erlang-1.0-alpine-3.22.1",
               "99.0.0-erlang-99.0-alpine-3.22.0"
             ]
    end

    test "a tag prefix drops the structured filters, matching the form", %{conn: conn} do
      body =
        conn
        |> get(~p"/api/docker?tag=1&erlang_version=26&os=debian")
        |> json_response(200)

      assert body["total"] == 2
    end
  end
end
