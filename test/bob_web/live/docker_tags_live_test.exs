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

    assert html =~ "<code>1.18.0-erlang-27.0-ubuntu-noble-20250101</code>"
    refute html =~ "<code>27.0-ubuntu-noble-20250101</code>"
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

    assert html =~ "<code>1.18.0-erlang-27.0-ubuntu-noble-20250101</code>"
    refute html =~ "<code>1.17.3-erlang-26.2-debian-bookworm-20250113-slim</code>"
    refute html =~ "<code>27.0-ubuntu-noble-20250101</code>"
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

    assert html =~ "<code>1.18.0-erlang-27.0-ubuntu-noble-20250101</code>"
    refute html =~ "<code>1.18.1-erlang-27.0-ubuntu-noble-20250101</code>"
    refute html =~ "<code>1.17.3-erlang-26.2-debian-bookworm-20250113-slim</code>"

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
end
