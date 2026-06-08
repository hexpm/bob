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
    <h2 class="text-lg font-semibold mb-4">Docker tags</h2>

    <form phx-change="search" phx-submit="search" class="flex flex-wrap gap-2 mb-4">
      <select name="repo" class="border rounded px-2 py-1 text-sm">
        <option value="">repo: any</option>
        <option :for={r <- @repos} value={r} selected={r == @repo}><%= r %></option>
      </select>
      <input
        type="text"
        name="tag"
        value={@tag}
        placeholder="tag prefix"
        class="border rounded px-2 py-1 text-sm"
      />
      <input
        type="text"
        name="elixir_version"
        value={@elixir_version}
        placeholder="Elixir"
        disabled={@tag != ""}
        class="border rounded px-2 py-1 text-sm"
      />
      <input
        type="text"
        name="erlang_version"
        value={@erlang_version}
        placeholder="Erlang"
        disabled={@tag != ""}
        class="border rounded px-2 py-1 text-sm"
      />
      <select name="os" disabled={@tag != ""} class="border rounded px-2 py-1 text-sm">
        <option value="">os: any</option>
        <option :for={o <- @oses} value={o} selected={o == @os}><%= o %></option>
      </select>
      <input
        type="text"
        name="os_version"
        value={@os_version}
        placeholder="OS version"
        disabled={@tag != ""}
        class="border rounded px-2 py-1 text-sm"
      />
      <select name="arch" class="border rounded px-2 py-1 text-sm">
        <option value="">arch: any</option>
        <option :for={a <- @arches} value={a} selected={a == @arch}><%= a %></option>
      </select>
    </form>

    <.table :if={@results != []} rows={@results}>
      <:col :let={d} label="repo"><%= d.repo %></:col>
      <:col :let={d} label="tag"><code><%= d.tag %></code></:col>
      <:col :let={d} label="archs"><%= Enum.join(d.archs, ", ") %></:col>
      <:col :let={d} label="built"><%= fmt(d.built_at) %></:col>
    </.table>
    <p :if={@results == []} class="text-sm text-gray-500">No matching tags.</p>

    <div class="flex gap-2 mt-3 text-sm">
      <button phx-click="page" phx-value-dir="prev" disabled={@offset == 0} class="px-2 py-1 border rounded disabled:opacity-40">Prev</button>
      <button phx-click="page" phx-value-dir="next" disabled={length(@results) < @page} class="px-2 py-1 border rounded disabled:opacity-40">Next</button>
    </div>
    """
  end
end
