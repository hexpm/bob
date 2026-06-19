defmodule BobWeb.ArtifactsLive do
  use BobWeb, :live_view

  alias Bob.Artifacts.ArtifactSearch

  @page ArtifactSearch.page_size()
  @filter_keys ArtifactSearch.filter_keys()

  @impl true
  def mount(_params, _session, socket) do
    socket =
      assign(socket,
        page: @page,
        kinds: [],
        arches: [],
        oses: [],
        total: nil,
        loading: true,
        results: []
      )

    socket = if connected?(socket), do: load_options(socket), else: socket
    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket = assign(socket, filter_assigns(params))
    socket = if connected?(socket), do: load(socket), else: socket
    {:noreply, socket}
  end

  @impl true
  def handle_event("search", params, socket) do
    filters = Keyword.delete(filter_assigns(params), :offset)
    {:noreply, push_patch(socket, to: ~p"/artifacts?#{query(filters, 0)}", replace: true)}
  end

  def handle_event("page", %{"dir" => dir}, socket) do
    offset = max(socket.assigns.offset + step(dir), 0)
    filters = Enum.map(@filter_keys, &{&1, socket.assigns[&1]})
    {:noreply, push_patch(socket, to: ~p"/artifacts?#{query(filters, offset)}")}
  end

  defp step("next"), do: @page
  defp step("prev"), do: -@page

  defp filter_assigns(params) do
    filters = ArtifactSearch.parse_filters(params)

    Enum.map(@filter_keys, &{&1, filters[&1]}) ++ [offset: ArtifactSearch.parse_offset(params)]
  end

  defp query(filters, offset) do
    filters = Enum.reject(filters, fn {_key, value} -> value in [nil, ""] end)
    if offset > 0, do: filters ++ [offset: offset], else: filters
  end

  defp load_options(socket) do
    assign(socket,
      kinds: Bob.Artifacts.distinct_kinds(),
      arches: Bob.Artifacts.distinct_arches(),
      oses: Bob.Artifacts.distinct_oses()
    )
  end

  defp load(socket) do
    %{query: q, kind: kind, arch: arch, os: os, offset: offset} = socket.assigns

    filters = %{query: q, kind: kind, arch: arch, os: os}

    %{results: results, total: total} = Bob.Artifacts.artifact_page(filters, @page, offset)

    assign(socket, results: results, total: total, loading: false)
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
          <span class="filter-bar__meta"><%= artifact_count_label(@total) %></span>
        </form>

        <div :if={@loading} class="empty-mini">Loading artifacts...</div>

        <.table :if={!@loading and @results != []} rows={@results} class="jt--art">
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
        <div :if={!@loading and @results == []} class="empty-mini">No matching artifacts.</div>

        <.pager
          :if={!@loading}
          event="page"
          offset={@offset}
          count={length(@results)}
          page={@page}
          unit="artifacts"
          total={@total}
        />
      </section>
    </div>
    """
  end

  defp artifact_count_label(nil), do: "Loading artifacts"

  defp artifact_count_label(count) do
    "#{format_count(count)} #{format_unit("artifacts", count)}"
  end
end
