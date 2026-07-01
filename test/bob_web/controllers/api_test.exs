defmodule BobWeb.ApiTest do
  use BobWeb.ConnCase

  alias Bob.Artifacts
  alias Bob.Artifacts.Artifact

  setup do
    Bob.FakeHttpClient.reset()
    Application.put_env(:bob, :agent_secret, "secret")
    on_exit(fn -> Application.delete_env(:bob, :agent_secret) end)
    :ok
  end

  defp artifact_body() do
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

  test "POST /api/artifacts/add upserts an artifact and returns 204", %{conn: conn} do
    Bob.FakeHttpClient.stub(
      :put,
      "https://s3.amazonaws.com/s3.hex.pm/builds/otp/amd64/ubuntu-24.04/builds.txt",
      200,
      ""
    )

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "secret")
      |> post(~p"/api/artifacts/add", artifact_body())

    assert conn.status == 204

    assert [%Artifact{name: "OTP-27.0", ref: "abc123", built_at: ~U[2026-01-02 03:04:05.000000Z]}] =
             Repo.all(Artifact)
  end

  test "POST /api/artifacts/add rejects a missing secret with 401", %{conn: conn} do
    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/artifacts/add", artifact_body())

    assert conn.status == 401
    assert Repo.all(Artifact) == []
  end

  test "POST /api/artifacts/add rejects an invalid secret before parsing the body", %{conn: conn} do
    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "public")
      |> post(~p"/api/artifacts/add", "{")

    assert conn.status == 401
    assert Repo.all(Artifact) == []
  end

  test "POST /api/docker/add upserts a docker tag and returns 204", %{conn: conn} do
    body =
      Bob.Plug.ErlangFormat.encode_to_iodata!(%{
        repo: "hexpm/erlang-amd64",
        tag: "27.0-ubuntu-noble-20250101",
        archs: ["amd64"]
      })

    conn =
      conn
      |> put_req_header("content-type", "application/vnd.bob+erlang")
      |> put_req_header("authorization", "secret")
      |> post(~p"/api/docker/add", body)

    assert conn.status == 204

    assert Artifacts.docker_tags("hexpm/erlang-amd64") ==
             [{"27.0-ubuntu-noble-20250101", ["amd64"]}]
  end

  test "POST /api/docker/add rejects a missing secret with 401", %{conn: conn} do
    body =
      Bob.Plug.ErlangFormat.encode_to_iodata!(%{
        repo: "hexpm/erlang-amd64",
        tag: "27.0-ubuntu-noble-20250101",
        archs: ["amd64"]
      })

    conn =
      conn
      |> put_req_header("content-type", "application/vnd.bob+erlang")
      |> post(~p"/api/docker/add", body)

    assert conn.status == 401
    assert Artifacts.docker_tags("hexpm/erlang-amd64") == []
  end

  test "POST /api/queue/add with erlang body enqueues a job (atom-keyed params)", %{conn: conn} do
    body =
      Bob.Plug.ErlangFormat.encode_to_iodata!(%{
        module: Bob.Job.OTPChecker,
        args: [:tags]
      })

    conn =
      conn
      |> put_req_header("content-type", "application/vnd.bob+erlang")
      |> put_req_header("authorization", "secret")
      |> post(~p"/api/queue/add", body)

    assert conn.status == 204
    assert [{Bob.Job.OTPChecker, [:tags]}] = Bob.Queue.queued()
  end

  test "POST /api/queue/requeue puts a running job back in the queue", %{conn: conn} do
    Bob.Queue.add(Bob.Job.OTPChecker, [:tags])
    {:ok, {id, [:tags]}} = Bob.Queue.start(Bob.Job.OTPChecker)

    body = Bob.Plug.ErlangFormat.encode_to_iodata!(%{id: id})

    conn =
      conn
      |> put_req_header("content-type", "application/vnd.bob+erlang")
      |> put_req_header("authorization", "secret")
      |> post(~p"/api/queue/requeue", body)

    assert conn.status == 204
    assert [{Bob.Job.OTPChecker, [:tags]}] = Bob.Queue.queued()
  end

  test "GET /status still returns 200 at the root", %{conn: conn} do
    conn = get(conn, "/status")
    assert conn.status == 200
  end
end
