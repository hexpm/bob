defmodule BobWeb.RequestLiveTest do
  use BobWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Bob.Artifacts.BaseImageTag
  alias Bob.BuildRequests.BuildRequest
  alias Bob.Queue.Job

  @builds_txt_url "https://s3.amazonaws.com/s3.hex.pm/builds/elixir/builds.txt"

  setup %{conn: conn} do
    Bob.FakeHttpClient.reset()
    Bob.FakeGitHub.reset()
    Bob.Cache.clear()

    Repo.insert!(%BaseImageTag{repo: "library/ubuntu", tag: "noble-20250101"})
    Bob.FakeGitHub.stub_refs("erlang/otp", [{"OTP-27.0", "sha1"}, {"OTP-27.0.1", "sha2"}])
    Bob.FakeHttpClient.stub(:get, @builds_txt_url, 200, "v1.18.0-otp-27 abc123\n")

    {:ok, conn: conn}
  end

  defp log_in(conn) do
    init_test_session(conn, %{
      "current_user" => %{"username" => "eric"},
      "token_expires_at" => System.system_time(:second) + 1800
    })
  end

  defp select_erlang(view, erlang) do
    view
    |> element("form")
    |> render_change(%{
      "kind" => "erlang",
      "os" => "ubuntu",
      "os_version" => "noble-20250101",
      "erlang" => erlang
    })
  end

  test "redirects anonymous users to the login page", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/oauth/login"}}} = live(conn, ~p"/request")
  end

  test "renders the form for a logged in user", %{conn: conn} do
    {:ok, view, html} = live(log_in(conn), ~p"/request")

    assert html =~ "Request a build"
    assert html =~ "Loading versions"
    refute render_async(view) =~ "Loading versions"

    html = view |> element("form") |> render_change(%{"kind" => "erlang", "os" => "ubuntu"})
    assert html =~ "noble-20250101"
  end

  test "offers only erlang versions the build rules allow", %{conn: conn} do
    Bob.FakeGitHub.stub_refs("erlang/otp", [{"OTP-27.0", "sha1"}, {"OTP-24.1", "sha2"}])

    {:ok, view, _html} = live(log_in(conn), ~p"/request")
    render_async(view)

    html = select_erlang(view, "")

    assert html =~ "27.0"
    refute html =~ ">24.1<"
  end

  test "submits an erlang build request", %{conn: conn} do
    {:ok, view, _html} = live(log_in(conn), ~p"/request")
    render_async(view)
    select_erlang(view, "27.0")

    html =
      view
      |> element("form")
      |> render_submit(%{
        "kind" => "erlang",
        "os" => "ubuntu",
        "os_version" => "noble-20250101",
        "erlang" => "27.0"
      })

    assert html =~ "Build queued"
    assert html =~ "27.0-ubuntu-noble-20250101"

    assert [%BuildRequest{username: "eric", kind: "erlang", erlang: "27.0"}] =
             Repo.all(BuildRequest)

    assert Enum.count(Repo.all(Job)) == 2
  end

  test "submits an elixir build request and explains the staged erlang base", %{conn: conn} do
    {:ok, view, _html} = live(log_in(conn), ~p"/request")
    render_async(view)

    params = %{
      "kind" => "elixir",
      "os" => "ubuntu",
      "os_version" => "noble-20250101",
      "elixir_build" => "1.18.0-otp-27",
      "erlang" => "27.0"
    }

    html = view |> element("form") |> render_change(params)
    assert html =~ "does not exist yet"

    html = view |> element("form") |> render_submit(params)
    assert html =~ "Build queued"

    assert [%BuildRequest{kind: "elixir", elixir: "1.18.0", erlang: "27.0", builds_count: 4}] =
             Repo.all(BuildRequest)

    assert Repo.all(Job) |> Enum.map(& &1.module_key) |> Enum.sort() ==
             Enum.sort([
               {Bob.Job.BuildDockerErlang, "amd64"},
               {Bob.Job.BuildDockerErlang, "arm64"}
             ])
  end

  test "reports already built tags", %{conn: conn} do
    Bob.Artifacts.add_docker_tag("hexpm/erlang-amd64", "27.0-ubuntu-noble-20250101", ["amd64"])
    Bob.Artifacts.add_docker_tag("hexpm/erlang-arm64", "27.0-ubuntu-noble-20250101", ["arm64"])

    {:ok, view, _html} = live(log_in(conn), ~p"/request")
    render_async(view)
    select_erlang(view, "27.0")

    html =
      view
      |> element("form")
      |> render_submit(%{
        "kind" => "erlang",
        "os" => "ubuntu",
        "os_version" => "noble-20250101",
        "erlang" => "27.0"
      })

    assert html =~ "already built"
    assert Repo.all(BuildRequest) == []
    assert Repo.all(Job) == []
  end

  test "rejects submissions over the hourly build limit", %{conn: conn} do
    {:ok, _request} =
      Bob.BuildRequests.create(%{
        username: "eric",
        kind: "erlang",
        erlang: "26.0",
        os: "ubuntu",
        os_version: "noble-20250101",
        builds_count: 10
      })

    {:ok, view, _html} = live(log_in(conn), ~p"/request")
    render_async(view)
    select_erlang(view, "27.0")

    html =
      view
      |> element("form")
      |> render_submit(%{
        "kind" => "erlang",
        "os" => "ubuntu",
        "os_version" => "noble-20250101",
        "erlang" => "27.0"
      })

    assert html =~ "limit of 10 requested builds"
    assert Repo.all(Job) == []
  end

  test "rejects values outside the option lists", %{conn: conn} do
    {:ok, view, _html} = live(log_in(conn), ~p"/request")
    render_async(view)

    html =
      view
      |> element("form")
      |> render_submit(%{
        "kind" => "erlang",
        "os" => "ubuntu",
        "os_version" => "noble-20250101",
        "erlang" => "24.1"
      })

    assert html =~ "Select a value for every field"
    assert Repo.all(Job) == []
    assert Repo.all(BuildRequest) == []
  end

  test "lists the user's recent requests", %{conn: conn} do
    {:ok, _request} =
      Bob.BuildRequests.create(%{
        username: "eric",
        kind: "erlang",
        erlang: "26.0",
        os: "ubuntu",
        os_version: "noble-20250101",
        builds_count: 2
      })

    {:ok, _view, html} = live(log_in(conn), ~p"/request")

    assert html =~ "Your recent requests"
    assert html =~ "26.0-ubuntu-noble-20250101"
    assert html =~ "pending"
  end
end
