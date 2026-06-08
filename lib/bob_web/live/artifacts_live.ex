defmodule BobWeb.ArtifactsLive do
  use BobWeb, :live_view

  @page 100

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(
        query: "",
        kind: "",
        arch: "",
        os: "",
        offset: 0,
        page: @page,
        kinds: Bob.Artifacts.distinct_kinds(),
        arches: Bob.Artifacts.distinct_arches(),
        oses: Bob.Artifacts.distinct_oses()
      )
      |> load()

    {:ok, socket}
  end

  @impl true
  def handle_event("search", params, socket) do
    socket =
      socket
      |> assign(
        query: params["query"] || "",
        kind: params["kind"] || "",
        arch: params["arch"] || "",
        os: params["os"] || "",
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

  defp load(socket) do
    %{query: q, kind: kind, arch: arch, os: os, offset: offset} = socket.assigns

    results =
      Bob.Artifacts.search_artifacts(
        %{query: q, kind: kind, arch: arch, os: os},
        @page,
        offset
      )

    assign(socket, results: results)
  end

  defp fmt(nil), do: "—"
  defp fmt(datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")

  defp truncate(nil, _length), do: nil

  defp truncate(value, length) when byte_size(value) > length do
    binary_part(value, 0, length) <> "..."
  end

  defp truncate(value, _length), do: value

  @impl true
  def render(assigns) do
    ~H"""
    <div class="fade-in">
      <div class="page-head">
        <div class="page-head__main">
          <h1>Build artifacts</h1>
        </div>
      </div>

      <section class="sec">
        <form phx-change="search" phx-submit="search" class="filter-bar filter-bar--wrap">
          <.search_box name="query" value={@query} placeholder="Search name or ref..." />
          <.filter_select name="kind" label="kind" value={@kind} options={@kinds} />
          <.filter_select name="arch" label="arch" value={@arch} options={@arches} />
          <.filter_select name="os" label="os" value={@os} options={@oses} />
          <span class="filter-bar__meta"><%= length(@results) %> artifacts</span>
        </form>

        <.table :if={@results != []} rows={@results} class="jt--art">
          <:col :let={a} label="kind">
            <span class="kind-badge"><%= a.kind %></span>
          </:col>
          <:col :let={a} label="arch">
            <span class="arch-tag"><%= a.arch %></span>
          </:col>
          <:col :let={a} label="os">
            <span class="os-cell"><%= a.os %></span>
          </:col>
          <:col :let={a} label="name">
            <code class="mono-cell mono-cell--name"><%= a.name %></code>
          </:col>
          <:col :let={a} label="ref">
            <code class="mono-cell" title={a.ref}><%= truncate(a.ref, 12) %></code>
          </:col>
          <:col :let={a} label="sha256">
            <code :if={a.sha256} class="mono-cell mono-cell--dim" title={a.sha256}>
              <%= truncate(a.sha256, 14) %>
            </code>
            <span :if={!a.sha256} class="mono-cell mono-cell--dim">—</span>
          </:col>
          <:col :let={a} label="built" class="col-time">
            <span class="c-time"><%= fmt(a.built_at) %></span>
          </:col>
        </.table>
        <div :if={@results == []} class="empty-mini">No matching artifacts.</div>

        <.pager
          event="page"
          offset={@offset}
          count={length(@results)}
          page={@page}
          unit="artifacts"
        />
      </section>
    </div>
    """
  end
end
