defmodule BobWeb.RequestLiveTest do
  use BobWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Bob.Artifacts.BaseImageTag
  alias Bob.BuildRequests.BuildRequest
  alias Bob.Queue.Job

  setup %{conn: conn} do
    Bob.FakeGitHub.reset()
    Bob.Cache.clear()

    Repo.insert!(%BaseImageTag{repo: "library/ubuntu", tag: "noble-20250101"})
    Bob.FakeGitHub.stub_refs("erlang/otp", [{"OTP-27.0", "sha1"}, {"OTP-27.0.1", "sha2"}])

    Bob.FakeGitHub.stub_releases("elixir-lang/elixir", [
      %{
        "tag_name" => "v1.18.0",
        "assets" => [%{"name" => "elixir-otp-27.zip"}]
      }
    ])

    {:ok, conn: conn}
  end

  defp log_in(conn) do
    init_test_session(conn, %{
      "current_user" => %{"username" => "eric"},
      "token_expires_at" => System.system_time(:second) + 1800
    })
  end

  defp select_names(html) do
    ~r/<select name="([^"]+)"/
    |> Regex.scan(html, capture: :all_but_first)
    |> List.flatten()
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
    html = render_async(view)
    refute html =~ "Loading versions"
    refute html =~ "choose"
    assert html =~ "Pending requests"
    assert html =~ "No pending requests."

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

  test "offers erlang before bare elixir releases and infers OTP from erlang", %{conn: conn} do
    Bob.FakeGitHub.stub_refs("erlang/otp", [{"OTP-27.0", "sha1"}, {"OTP-28.0", "sha2"}])

    Bob.FakeGitHub.stub_releases("elixir-lang/elixir", [
      %{"tag_name" => "v1.19.0", "assets" => [%{"name" => "elixir-otp-28.zip"}]},
      %{"tag_name" => "v1.18.0", "assets" => [%{"name" => "elixir-otp-27.zip"}]}
    ])

    {:ok, view, _html} = live(log_in(conn), ~p"/request")
    render_async(view)

    html =
      view
      |> element("form")
      |> render_change(%{
        "kind" => "elixir",
        "os" => "ubuntu",
        "os_version" => "noble-20250101"
      })

    assert select_names(html) == ["kind", "os", "os_version", "erlang", "elixir"]
    assert html =~ "27.0"
    assert html =~ "28.0"
    refute html =~ ~s(value="1.19.0")
    refute html =~ ~s(value="1.18.0")
    refute html =~ "otp-"

    html =
      view
      |> element("form")
      |> render_change(%{
        "kind" => "elixir",
        "os" => "ubuntu",
        "os_version" => "noble-20250101",
        "erlang" => "27.0"
      })

    assert html =~ ~s(value="1.18.0")
    refute html =~ ~s(value="1.19.0")
    refute html =~ "otp-"
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
      "elixir" => "1.18.0",
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
    Bob.Artifacts.add_docker_tag("hexpm/erlang", "27.0-ubuntu-noble-20250101", ["amd64", "arm64"])

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

  test "replaces old flash messages", %{conn: conn} do
    Bob.Artifacts.add_docker_tag("hexpm/erlang-amd64", "27.0-ubuntu-noble-20250101", ["amd64"])
    Bob.Artifacts.add_docker_tag("hexpm/erlang-arm64", "27.0-ubuntu-noble-20250101", ["arm64"])
    Bob.Artifacts.add_docker_tag("hexpm/erlang", "27.0-ubuntu-noble-20250101", ["amd64", "arm64"])

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
    refute html =~ "already built"
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

  test "lists recent requests across all users", %{conn: conn} do
    {:ok, _mine} =
      Bob.BuildRequests.create(%{
        username: "eric",
        kind: "erlang",
        erlang: "26.0",
        os: "ubuntu",
        os_version: "noble-20250101",
        builds_count: 2
      })

    {:ok, others} =
      Bob.BuildRequests.create(%{
        username: "jose",
        kind: "erlang",
        erlang: "28.0",
        os: "ubuntu",
        os_version: "noble-20250101",
        builds_count: 2
      })

    others
    |> Ecto.Changeset.change(state: "completed")
    |> Repo.update!()

    {:ok, _view, html} = live(log_in(conn), ~p"/request")

    assert html =~ "Recent requests"
    # Another user's request, in a finished state, still shows up.
    assert html =~ "jose"
    assert html =~ "28.0-ubuntu-noble-20250101"
    assert html =~ "26.0-ubuntu-noble-20250101"
  end

  test "lists global pending requests", %{conn: conn} do
    {:ok, _my_request} =
      Bob.BuildRequests.create(%{
        username: "eric",
        kind: "erlang",
        erlang: "26.0",
        os: "ubuntu",
        os_version: "noble-20250101",
        builds_count: 2
      })

    {:ok, _other_request} =
      Bob.BuildRequests.create(%{
        username: "jose",
        kind: "elixir",
        elixir: "1.18.0",
        erlang: "27.0",
        os: "ubuntu",
        os_version: "noble-20250101",
        builds_count: 4
      })

    {:ok, _view, html} = live(log_in(conn), ~p"/request")

    assert html =~ "Pending requests"
    assert html =~ "jose"
    assert html =~ "1.18.0-erlang-27.0-ubuntu-noble-20250101"
  end
end
