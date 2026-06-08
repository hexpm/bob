defmodule BobWeb.DockerTagsLive do
  use BobWeb, :live_view

  @page 100

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(
        repo: "",
        tag: "",
        arch: "",
        elixir_version: "",
        erlang_version: "",
        os: "",
        os_version: "",
        offset: 0,
        page: @page,
        repos: Bob.Artifacts.distinct_repos(),
        arches: Bob.Artifacts.distinct_docker_arches(),
        oses: Bob.Artifacts.distinct_docker_oses()
      )
      |> load()

    {:ok, socket}
  end

  @impl true
  def handle_event("search", params, socket) do
    tag = params["tag"] || ""

    socket =
      socket
      |> assign(
        repo: params["repo"] || "",
        tag: tag,
        arch: params["arch"] || "",
        elixir_version: structured_param(params, "elixir_version", tag),
        erlang_version: structured_param(params, "erlang_version", tag),
        os: structured_param(params, "os", tag),
        os_version: structured_param(params, "os_version", tag),
        offset: 0
      )
      |> load()

    {:noreply, socket}
  end

  def handle_event("page", %{"dir" => dir}, socket) do
    offset = max(socket.assigns.offset + step(dir), 0)
    {:noreply, socket |> assign(offset: offset) |> load()}
  end

  defp step("next"), do: @page
  defp step("prev"), do: -@page

  defp structured_param(_params, _key, tag) when tag != "", do: ""
  defp structured_param(params, key, _tag), do: params[key] || ""

  defp load(socket) do
    %{
      repo: repo,
      tag: tag,
      arch: arch,
      elixir_version: elixir_version,
      erlang_version: erlang_version,
      os: os,
      os_version: os_version,
      offset: offset
    } = socket.assigns

    results =
      Bob.Artifacts.search_docker_tags(
        %{
          repo: repo,
          tag: tag,
          arch: arch,
          elixir_version: elixir_version,
          erlang_version: erlang_version,
          os: os,
          os_version: os_version
        },
        @page,
        offset
      )

    assign(socket, results: results)
  end

  defp fmt(nil), do: "—"
  defp fmt(datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")

  @impl true
  def render(assigns) do
    ~H"""
    <div class="fade-in">
      <div class="page-head">
        <div class="page-head__main">
          <h1>Docker tags</h1>
        </div>
      </div>

      <section class="sec">
        <form phx-change="search" phx-submit="search" class="filter-bar filter-bar--wrap dk-filters">
          <.filter_select name="repo" label="repo" value={@repo} options={@repos} />
          <.filter_text name="tag" value={@tag} placeholder="tag prefix..." />
          <span class={["f-or", @tag != "" && "f-or--off"]}>or</span>
          <div class={["fgroup", @tag != "" && "fgroup--off"]}>
            <.filter_text
              name="elixir_version"
              value={@elixir_version}
              placeholder="Elixir"
              disabled={@tag != ""}
            />
            <.filter_text
              name="erlang_version"
              value={@erlang_version}
              placeholder="Erlang"
              disabled={@tag != ""}
            />
            <.filter_select
              name="os"
              label="os"
              value={@os}
              options={@oses}
              disabled={@tag != ""}
            />
            <.filter_text
              name="os_version"
              value={@os_version}
              placeholder="OS version"
              disabled={@tag != ""}
            />
          </div>
          <.filter_select name="arch" label="arch" value={@arch} options={@arches} />
          <span class="filter-bar__meta"><%= length(@results) %> tags</span>
        </form>

        <.table :if={@results != []} rows={@results} class="jt--dk">
          <:col :let={d} label="repo">
            <div class="dk-repo">
              <.icon name="docker" class="icon-blue" />
              <code class="mono-cell mono-cell--name"><%= d.repo %></code>
            </div>
          </:col>
          <:col :let={d} label="tag">
            <code><%= d.tag %></code>
          </:col>
          <:col :let={d} label="archs">
            <div class="arch-list">
              <span :for={arch <- d.archs} class="arch-tag"><%= arch %></span>
            </div>
          </:col>
          <:col :let={d} label="built" class="col-time">
            <span class="c-time"><%= fmt(d.built_at) %></span>
          </:col>
        </.table>
        <div :if={@results == []} class="empty-mini">No matching tags.</div>

        <.pager event="page" offset={@offset} count={length(@results)} page={@page} unit="tags" />
      </section>
    </div>
    """
  end
end
