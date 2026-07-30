defmodule BobWeb.DockerTagsLiveTest do
  use BobWeb.ConnCase

  import Phoenix.LiveViewTest

  setup do
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
      "1.18.1-erlang-27.0-ubuntu-noble-20250101",
      ["arm64"]
    )

    Bob.Artifacts.add_docker_tag(
      "hexpm/elixir",
      "1.17.3-erlang-26.2-debian-bookworm-20250113-slim",
      ["amd64"]
    )

    :ok
  end

  test "lists tags and filters by tag prefix", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/docker")
    assert html =~ "27.0-ubuntu-noble-20250101"
    assert html =~ "1.18.0-erlang-27.0-ubuntu-noble-20250101"
    assert html =~ "4 tags"
    assert html =~ ~r/Showing\s*<b>1<\/b>\s*-\s*<b>4<\/b>\s*tags\s*of\s*4 tags/

    html =
      render_change(view, "search", %{
        "repo" => "",
        "tag" => "1.18",
        "arch" => "",
        "elixir_version" => "",
        "erlang_version" => "",
        "os" => "",
        "os_version" => ""
      })

    assert docker_tag?(html, "1.18.0-erlang-27.0-ubuntu-noble-20250101")
    refute docker_tag?(html, "27.0-ubuntu-noble-20250101")
  end

  test "flags per-arch tags nearing removal and never manifest tags", %{conn: conn} do
    now = DateTime.utc_now()

    # per-arch built long ago -> removing
    Bob.Artifacts.add_docker_tag(
      "hexpm/elixir-amd64",
      "1.10.0-erlang-23.0-ubuntu-noble-20200101",
      ["amd64"],
      DateTime.add(now, -90, :day)
    )

    # manifest repos are not pruned, so however old the build, no warning
    Bob.Artifacts.add_docker_tag(
      "hexpm/erlang",
      "26.0-ubuntu-noble-20250101",
      ["amd64", "arm64"],
      DateTime.add(now, -300, :day)
    )

    {:ok, _view, html} = live(conn, ~p"/docker")

    assert removing?(html, "1.10.0-erlang-23.0-ubuntu-noble-20200101")
    refute removing?(html, "26.0-ubuntu-noble-20250101")
  end

  test "a reserved tag is not also flagged as removing", %{conn: conn} do
    Bob.Artifacts.add_docker_tag(
      "hexpm/elixir-amd64",
      "1.18.0-erlang-27.0-ubuntu-noble-20250101",
      ["amd64"],
      DateTime.add(DateTime.utc_now(), -90, :day)
    )

    Bob.BuildRequests.create(%{
      username: "eric",
      kind: "elixir",
      elixir: "1.18.0",
      erlang: "27.0",
      os: "ubuntu",
      os_version: "noble-20250101",
      builds_count: 0
    })

    {:ok, _view, html} = live(conn, ~p"/docker")

    assert reserved?(html, "1.18.0-erlang-27.0-ubuntu-noble-20250101")
    refute removing?(html, "1.18.0-erlang-27.0-ubuntu-noble-20250101")
  end

  test "flags tags reserved by a build request", %{conn: conn} do
    Bob.BuildRequests.create(%{
      username: "eric",
      kind: "elixir",
      elixir: "1.18.0",
      erlang: "27.0",
      os: "ubuntu",
      os_version: "noble-20250101",
      builds_count: 0
    })

    {:ok, _view, html} = live(conn, ~p"/docker")

    assert reserved?(html, "1.18.0-erlang-27.0-ubuntu-noble-20250101")
    refute reserved?(html, "1.18.1-erlang-27.0-ubuntu-noble-20250101")
    refute reserved?(html, "27.0-ubuntu-noble-20250101")
  end

  test "applies filters from URL params on load", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/docker?tag=1.18")

    assert docker_tag?(html, "1.18.0-erlang-27.0-ubuntu-noble-20250101")
    refute docker_tag?(html, "27.0-ubuntu-noble-20250101")
    assert control_html(html, "tag") =~ ~s(value="1.18")
  end

  test "searching patches the URL so filters survive a refresh", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/docker")

    render_change(view, "search", %{
      "repo" => "",
      "tag" => "1.18",
      "arch" => "",
      "elixir_version" => "",
      "erlang_version" => "",
      "os" => "",
      "os_version" => ""
    })

    assert_patch(view, ~p"/docker?tag=1.18")
  end

  test "filters by structured inputs", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/docker")

    html =
      render_change(view, "search", %{
        "repo" => "hexpm/elixir",
        "tag" => "",
        "arch" => "arm",
        "elixir_version" => "1.18",
        "erlang_version" => "27",
        "os" => "ub",
        "os_version" => "noble"
      })

    assert docker_tag?(html, "1.18.0-erlang-27.0-ubuntu-noble-20250101")
    refute docker_tag?(html, "1.17.3-erlang-26.2-debian-bookworm-20250113-slim")
    refute docker_tag?(html, "27.0-ubuntu-noble-20250101")
  end

  test "tag prefix keeps arch filtering and disables parsed tag filters", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/docker")

    html =
      render_change(view, "search", %{
        "repo" => "hexpm/elixir",
        "tag" => "1.18",
        "arch" => "amd64",
        "elixir_version" => "1.17",
        "erlang_version" => "26",
        "os" => "debian",
        "os_version" => "bookworm"
      })

    assert docker_tag?(html, "1.18.0-erlang-27.0-ubuntu-noble-20250101")
    refute docker_tag?(html, "1.18.1-erlang-27.0-ubuntu-noble-20250101")
    refute docker_tag?(html, "1.17.3-erlang-26.2-debian-bookworm-20250113-slim")

    refute control_html(html, "arch") =~ "disabled"

    for name <- ~w(elixir_version erlang_version os os_version) do
      assert control_html(html, name) =~ "disabled"
    end
  end

  test "renders every Docker search input", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/docker")

    assert control_html(html, "repo") =~ "<select"
    assert control_html(html, "tag") =~ ~s(type="text")
    assert control_html(html, "arch") =~ "<select"
    assert html =~ ~s(name="elixir_version")
    assert html =~ ~s(name="erlang_version")
    assert control_html(html, "os") =~ "<select"
    assert html =~ ~s(name="os_version")

    assert html =~ ~s(<option value="hexpm/elixir">hexpm/elixir</option>)
    assert html =~ ~s(<option value="hexpm/erlang">hexpm/erlang</option>)
    assert html =~ ~s(<option value="amd64">amd64</option>)
    assert html =~ ~s(<option value="arm64">arm64</option>)
    assert html =~ ~s(<option value="debian">debian</option>)
    assert html =~ ~s(<option value="ubuntu">ubuntu</option>)
  end

  test "renders arch filter after the parsed tag filters", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/docker")

    assert control_position(html, "repo") < control_position(html, "tag")
    assert control_position(html, "tag") < control_position(html, "elixir_version")
    assert control_position(html, "elixir_version") < control_position(html, "erlang_version")
    assert control_position(html, "erlang_version") < control_position(html, "os")
    assert control_position(html, "os") < control_position(html, "os_version")
    assert control_position(html, "os_version") < control_position(html, "arch")
  end

  defp control_html(html, name) do
    Regex.run(~r/<(?:input|select)[^>]*name="#{name}"[^>]*>/, html)
    |> List.first()
  end

  defp control_position(html, name) do
    {position, _length} = :binary.match(html, ~s(name="#{name}"))
    position
  end

  defp docker_tag?(html, tag) do
    html =~ ~r/<code class="dk-tag-code"[^>]*>#{Regex.escape(tag)}<\/code>/
  end

  defp reserved?(html, tag) do
    html =~
      ~r/<code class="dk-tag-code"[^>]*>#{Regex.escape(tag)}<\/code>\s*<span[^>]*dk-reserved/
  end

  # Matches the removing badge anywhere in the tag's cell, not just directly
  # after </code>. Anchoring it tight made the "reserved tags are not also
  # flagged removing" refute unfalsifiable, since the reserved span is emitted
  # first and pushed dk-removing out of the pattern.
  defp removing?(html, tag) do
    html =~
      ~r/<code class="dk-tag-code"[^>]*>#{Regex.escape(tag)}<\/code>(?:(?!<\/div>).)*dk-removing/s
  end
end
