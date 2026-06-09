defmodule BobWeb.DockerTagsLive do
  use BobWeb, :live_view

  @page 100

  @impl true
  def mount(_params, _session, socket) do
    options = Bob.Artifacts.docker_tag_filter_options()

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
        repos: options.repos,
        arches: options.arches,
        oses: options.oses,
        total: nil,
        loading: true,
        results: []
      )

    socket = if connected?(socket), do: load(socket), else: socket

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

    filters = %{
      repo: repo,
      tag: tag,
      arch: arch,
      elixir_version: elixir_version,
      erlang_version: erlang_version,
      os: os,
      os_version: os_version
    }

    results =
      Bob.Artifacts.search_docker_tags(filters, @page, offset)

    total =
      if offset == 0 and results == [] do
        0
      else
        filters
        |> Bob.Artifacts.count_docker_tags()
        # The page and count are separate queries, so keep the pager coherent if
        # tags change between them.
        |> max(offset + length(results))
      end

    assign(socket, results: results, total: total, loading: false)
  end

  defp fmt(nil), do: "—"
  defp fmt(datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")

  defp count_label(nil), do: "Loading tags"
  defp count_label(0), do: "0 tags"
  defp count_label(count), do: "#{format_count(count)} #{format_unit("tags", count)}"

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
          <span class="filter-bar__meta"><%= count_label(@total) %></span>
        </form>

        <div :if={@loading} class="empty-mini">Loading tags...</div>

        <.table :if={!@loading and @results != []} rows={@results} class="jt--dk">
          <:col :let={d} label="repo" class="col-dk-repo">
            <div class="dk-repo">
              <.icon name="docker" class="icon-blue" />
              <code class="mono-cell mono-cell--name"><%= d.repo %></code>
            </div>
          </:col>
          <:col :let={d} label="tag" class="col-dk-tag">
            <code class="dk-tag-code" title={d.tag}><%= d.tag %></code>
          </:col>
          <:col :let={d} label="archs" class="col-dk-archs">
            <div class="arch-list">
              <span :for={arch <- d.archs} class="arch-tag"><%= arch %></span>
            </div>
          </:col>
          <:col :let={d} label="built" class="col-time">
            <span class="c-time"><%= fmt(d.built_at) %></span>
          </:col>
        </.table>
        <div :if={!@loading and @results == []} class="empty-mini">No matching tags.</div>

        <.pager
          :if={!@loading}
          event="page"
          offset={@offset}
          count={length(@results)}
          page={@page}
          unit="tags"
          total={@total}
        />
      </section>
    </div>
    """
  end
end
