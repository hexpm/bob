defmodule BobWeb.ArtifactsJsonTest do
  use BobWeb.ConnCase

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
    body = conn |> get(~p"/artifacts") |> json_response(200)

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
    body = conn |> get(~p"/artifacts?query=27.0") |> json_response(200)

    assert body["total"] == 1
    assert Enum.map(body["artifacts"], & &1["name"]) == ["OTP-27.0"]
  end

  test "filters by kind, arch and os", %{conn: conn} do
    body = conn |> get(~p"/artifacts?arch=arm64") |> json_response(200)

    assert Enum.map(body["artifacts"], & &1["name"]) == ["OTP-26.2"]
  end

  test "browsers still get the LiveView HTML", %{conn: conn} do
    conn = conn |> delete_req_header("accept") |> get(~p"/artifacts")
    assert html_response(conn, 200) =~ "Build artifacts"
  end
end
