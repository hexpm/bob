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

    # The elixir image is built FROM this one, so the request holds it too.
    assert reserved?(html, "27.0-ubuntu-noble-20250101")
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

  test "sorts by clicked headers, combines columns, and keeps the sort in the URL", %{conn: conn} do
    Bob.Artifacts.add_docker_tag(
      "hexpm/elixir",
      "1.20.1-erlang-29.0.2-debian-trixie-20260610-slim",
      ["amd64", "arm64"],
      ~U[2025-01-01 00:00:00Z]
    )

    Bob.Artifacts.add_docker_tag(
      "hexpm/elixir",
      "1.9.4-erlang-22.3-debian-buster-20260101-slim",
      ["amd64", "arm64"],
      ~U[2026-01-01 00:00:00Z]
    )

    {:ok, view, html} =
      live(conn, ~p"/docker?repo=hexpm%2Felixir&sort=elixir_version")

    assert tag_position(html, "1.20.1-erlang-29.0.2-debian-trixie-20260610-slim") <
             tag_position(html, "1.9.4-erlang-22.3-debian-buster-20260101-slim")

    render_change(view, "search", %{
      "repo" => "hexpm/elixir",
      "tag" => "",
      "arch" => "",
      "elixir_version" => "1.20",
      "erlang_version" => "",
      "os" => "",
      "os_version" => ""
    })

    assert_patch(view, ~p"/docker?repo=hexpm%2Felixir&elixir_version=1.20&sort=elixir_version")

    view
    |> element("#docker-sort-erlang_version")
    |> render_click()

    assert_patch(
      view,
      "/docker?repo=hexpm%2Felixir&elixir_version=1.20&sort=elixir_version%2Cerlang_version"
    )

    html = render(view)
    assert html =~ ~s(aria-label="Remove Elixir sort, priority 1")
    assert html =~ ~s(aria-label="Remove Erlang sort, priority 2")

    view
    |> element("#docker-sort-elixir_version")
    |> render_click()

    assert_patch(view, ~p"/docker?repo=hexpm%2Felixir&elixir_version=1.20&sort=erlang_version")
  end

  test "defaults malformed sort params to build time", %{conn: conn} do
    {:ok, view, html} = live(conn, "/docker?sort[]=os")

    assert html =~ ~s(aria-label="built sort, descending, priority 1")
    assert has_element?(view, "#docker-sort-built_at[disabled]")
  end

  test "treats build time as an exclusive sort", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/docker?sort=elixir_version%2Cerlang_version")

    view
    |> element("#docker-sort-built_at")
    |> render_click()

    assert_patch(view, ~p"/docker")
    assert has_element?(view, "#docker-sort-built_at[disabled]")

    view
    |> element("#docker-sort-elixir_version")
    |> render_click()

    assert_patch(view, ~p"/docker?sort=elixir_version")
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
    assert html =~ ~s(id="docker-sort-elixir_version")
    assert html =~ ~s(id="docker-sort-erlang_version")
    assert html =~ ~s(id="docker-sort-os")
    assert html =~ ~s(id="docker-sort-os_version")
    assert html =~ ~s(id="docker-sort-built_at")
    assert html =~ ~s(aria-label="built sort, descending, priority 1")
    assert html =~ ~r/id="docker-sort-built_at"[^>]*disabled/
  end

  test "renders parsed tag components in separate columns", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/docker")

    assert html =~ sortable_header("elixir_version", "Elixir")
    assert html =~ sortable_header("erlang_version", "Erlang")
    assert html =~ sortable_header("os", "OS")
    assert html =~ sortable_header("os_version", "OS version")
    assert html =~ ~r/<code class="dk-component">1\.18\.0<\/code>/
    assert html =~ ~r/<code class="dk-component">27\.0<\/code>/
    assert html =~ ~r/<code class="dk-component">ubuntu<\/code>/
    assert html =~ ~r/<code class="dk-component">noble-20250101<\/code>/
  end

  test "renders each tag as a clipboard control", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/docker")

    assert html =~
             ~r/<button[^>]*phx-hook="CopyToClipboard"[^>]*data-copy-text="1\.18\.0-erlang-27\.0-ubuntu-noble-20250101"/

    assert html =~ ~s(aria-label="Copy 1.18.0-erlang-27.0-ubuntu-noble-20250101")
    assert html =~ ~s(class="dk-tag-copy__icon dk-tag-copy__icon--copy")
    assert html =~ ~s(class="dk-tag-copy__icon dk-tag-copy__icon--copied")
    assert html =~ ~s(class="dk-tag-copy__icon dk-tag-copy__icon--error")
    assert html =~ ~r/<span[^>]*data-copy-status[^>]*role="status"[^>]*aria-live="polite"/

    assert html =~
             ~s(title="1.18.0-erlang-27.0-ubuntu-noble-20250101">1.18.0-erlang-27.0-ubuntu-noble-20250101</code>)
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

  defp tag_position(html, tag) do
    {position, _length} = :binary.match(html, tag)
    position
  end

  defp sortable_header(field, label) do
    ~r/<th[^>]*>.*?<button[^>]*id="docker-sort-#{field}"[^>]*>.*?#{Regex.escape(label)}.*?<\/button>.*?<\/th>/s
  end

  defp reserved?(html, tag) do
    needle = ~s(data-copy-text="#{tag}")

    case Enum.find(String.split(html, "<tr"), &String.contains?(&1, needle)) do
      nil -> false
      row -> row =~ "dk-reserved"
    end
  end
end
