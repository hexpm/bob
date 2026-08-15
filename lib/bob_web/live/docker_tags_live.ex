defmodule BobWeb.DockerTagsLive do
  use BobWeb, :live_view

  alias Bob.Artifacts.DockerTagSearch

  @page DockerTagSearch.page_size()
  @filter_keys DockerTagSearch.filter_keys()

  @impl true
  def mount(_params, _session, socket) do
    options = Bob.Artifacts.docker_tag_filter_options()

    socket =
      assign(socket,
        page: @page,
        repos: options.repos,
        arches: options.arches,
        oses: options.oses,
        total: nil,
        loading: true,
        results: [],
        reserved: MapSet.new()
      )

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
    params = Map.put(params, "sort", DockerTagSearch.encode_sort(socket.assigns.sort))
    filters = Keyword.delete(filter_assigns(params), :offset)
    {:noreply, push_patch(socket, to: ~p"/docker?#{query(filters, 0)}", replace: true)}
  end

  def handle_event("sort", %{"field" => field}, socket) do
    sort = DockerTagSearch.toggle_sort(socket.assigns.sort, field)
    filters = current_filters(socket) ++ [sort: sort]
    {:noreply, push_patch(socket, to: ~p"/docker?#{query(filters, 0)}")}
  end

  def handle_event("page", %{"dir" => dir}, socket) do
    offset = max(socket.assigns.offset + step(dir), 0)
    filters = current_filters(socket) ++ [sort: socket.assigns.sort]
    {:noreply, push_patch(socket, to: ~p"/docker?#{query(filters, offset)}")}
  end

  defp step("next"), do: @page
  defp step("prev"), do: -@page

  defp filter_assigns(params) do
    filters = DockerTagSearch.parse_filters(params)

    Enum.map(@filter_keys, &{&1, filters[&1]}) ++
      [sort: DockerTagSearch.parse_sort(params), offset: DockerTagSearch.parse_offset(params)]
  end

  defp query(filters, offset) do
    filters =
      Enum.flat_map(filters, fn
        {:sort, sort} ->
          case DockerTagSearch.encode_sort(sort) do
            "built_at" -> []
            encoded -> [{:sort, encoded}]
          end

        {_key, value} when value in [nil, ""] ->
          []

        filter ->
          [filter]
      end)

    if offset > 0, do: filters ++ [offset: offset], else: filters
  end

  defp current_filters(socket), do: Enum.map(@filter_keys, &{&1, socket.assigns[&1]})

  defp load(socket) do
    %{
      repo: repo,
      tag: tag,
      arch: arch,
      elixir_version: elixir_version,
      erlang_version: erlang_version,
      os: os,
      os_version: os_version,
      sort: sort,
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

    %{results: results, total: total} =
      Bob.Artifacts.docker_tag_page(filters, @page, offset, sort)

    reserved = Bob.Artifacts.reserved_docker_tag_ids(results)

    assign(socket, results: results, total: total, loading: false, reserved: reserved)
  end

  defp fmt(nil), do: "—"
  defp fmt(datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")

  defp component(tag, key), do: Map.get(tag.search, key, "—")

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

        <.table
          :if={!@loading and @results != []}
          rows={@results}
          class="jt--dk"
          sort={@sort}
          sort_event="sort"
        >
          <:col :let={d} label="repo" class="col-dk-repo">
            <div class="dk-repo">
              <.icon name="docker" class="icon-blue" />
              <code class="mono-cell mono-cell--name"><%= d.repo %></code>
            </div>
          </:col>
          <:col :let={d} label="tag" class="col-dk-tag">
            <div class="dk-tag-cell">
              <button
                id={"docker-tag-copy-#{d.id}"}
                type="button"
                class="dk-tag-copy"
                phx-hook="CopyToClipboard"
                data-copy-text={d.tag}
                aria-label={"Copy #{d.tag}"}
                title="Copy tag"
              >
                <code class="dk-tag-code" title={d.tag}><%= d.tag %></code>
                <.icon
                  name="copy"
                  size={14}
                  class="dk-tag-copy__icon dk-tag-copy__icon--copy"
                />
                <.icon
                  name="check"
                  size={14}
                  class="dk-tag-copy__icon dk-tag-copy__icon--copied"
                />
                <.icon name="x" size={14} class="dk-tag-copy__icon dk-tag-copy__icon--error" />
                <span
                  class="dk-tag-copy__status"
                  data-copy-status
                  role="status"
                  aria-live="polite"
                >
                </span>
              </button>
              <span
                :if={MapSet.member?(@reserved, d.id)}
                class="dk-reserved"
                title="Reserved by a build request — exempt from cleanup"
              >
                reserved
              </span>
            </div>
          </:col>
          <:col
            :let={d}
            label="Elixir"
            class="col-dk-version"
            sort_field="elixir_version"
          >
            <code class="dk-component"><%= component(d, "elixir_version") %></code>
          </:col>
          <:col
            :let={d}
            label="Erlang"
            class="col-dk-version"
            sort_field="erlang_version"
          >
            <code class="dk-component"><%= component(d, "erlang_version") %></code>
          </:col>
          <:col :let={d} label="OS" class="col-dk-os" sort_field="os">
            <code class="dk-component"><%= component(d, "os") %></code>
          </:col>
          <:col
            :let={d}
            label="OS version"
            class="col-dk-os-version"
            sort_field="os_version"
          >
            <code class="dk-component"><%= component(d, "os_version") %></code>
          </:col>
          <:col :let={d} label="archs" class="col-dk-archs">
            <div class="arch-list">
              <span :for={arch <- d.archs} class="arch-tag"><%= arch %></span>
            </div>
          </:col>
          <:col :let={d} label="built" class="col-time" sort_field="built_at">
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
