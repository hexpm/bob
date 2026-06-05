defmodule Bob.RouterTest do
  use Bob.DataCase

  import Plug.Test
  import Plug.Conn

  alias Bob.Artifacts
  alias Bob.Artifacts.Artifact

  @opts Bob.Router.init([])

  setup do
    Bob.FakeHttpClient.reset()
    Application.put_env(:bob, :agent_secret, "secret")
    on_exit(fn -> Application.delete_env(:bob, :agent_secret) end)
    :ok
  end

  defp body() do
    JSON.encode!(%{
      kind: "otp",
      arch: "amd64",
      os: "ubuntu-24.04",
      name: "OTP-27.0",
      ref: "abc123",
      sha256: "deadbeef",
      date: "2026-01-02T03:04:05Z"
    })
  end

  test "POST /artifacts/add upserts an artifact and returns 204" do
    Bob.FakeHttpClient.stub(
      :put,
      "https://s3.amazonaws.com/s3.hex.pm/builds/otp/amd64/ubuntu-24.04/builds.txt",
      200,
      ""
    )

    conn =
      conn(:post, "/artifacts/add", body())
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "secret")
      |> Bob.Router.call(@opts)

    assert conn.status == 204

    assert [%Artifact{name: "OTP-27.0", ref: "abc123", built_at: ~U[2026-01-02 03:04:05.000000Z]}] =
             Repo.all(Artifact)
  end

  test "POST /artifacts/add rejects a missing/wrong secret with 401" do
    conn =
      conn(:post, "/artifacts/add", body())
      |> put_req_header("content-type", "application/json")
      |> Bob.Router.call(@opts)

    assert conn.status == 401
    assert Repo.all(Artifact) == []
  end

  test "POST /docker/add upserts a docker tag and returns 204" do
    body =
      Bob.Plug.ErlangFormat.encode_to_iodata!(%{
        repo: "hexpm/erlang-amd64",
        tag: "27.0-ubuntu-noble-20250101",
        archs: ["amd64"]
      })

    conn =
      conn(:post, "/docker/add", body)
      |> put_req_header("content-type", "application/vnd.bob+erlang")
      |> put_req_header("authorization", "secret")
      |> Bob.Router.call(@opts)

    assert conn.status == 204

    assert Artifacts.docker_tags("hexpm/erlang-amd64") ==
             [{"27.0-ubuntu-noble-20250101", ["amd64"]}]
  end

  test "POST /docker/add rejects a missing/wrong secret with 401" do
    body =
      Bob.Plug.ErlangFormat.encode_to_iodata!(%{
        repo: "hexpm/erlang-amd64",
        tag: "27.0-ubuntu-noble-20250101",
        archs: ["amd64"]
      })

    conn =
      conn(:post, "/docker/add", body)
      |> put_req_header("content-type", "application/vnd.bob+erlang")
      |> Bob.Router.call(@opts)

    assert conn.status == 401
    assert Artifacts.docker_tags("hexpm/erlang-amd64") == []
  end
end
