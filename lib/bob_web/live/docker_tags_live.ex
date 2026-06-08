defmodule BobWeb.DockerTagsLive do
  use BobWeb, :live_view

  @page 100

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(
        query: "",
        repo: "",
        offset: 0,
        page: @page,
        repos: Bob.Artifacts.distinct_repos()
      )
      |> load()

    {:ok, socket}
  end

  @impl true
  def handle_event("search", params, socket) do
    socket =
      socket
      |> assign(query: params["query"] || "", repo: params["repo"] || "", offset: 0)
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
    %{query: q, repo: repo, offset: offset} = socket.assigns
    results = Bob.Artifacts.search_docker_tags(%{query: q, repo: repo}, @page, offset)
    assign(socket, results: results)
  end

  defp fmt(nil), do: "—"
  defp fmt(datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")

  @impl true
  def render(assigns) do
    ~H"""
    <h2 class="text-lg font-semibold mb-4">Docker tags</h2>

    <form phx-change="search" phx-submit="search" class="flex flex-wrap gap-2 mb-4">
      <input
        type="text"
        name="query"
        value={@query}
        placeholder="Search tag…"
        class="border rounded px-2 py-1 text-sm"
      />
      <select name="repo" class="border rounded px-2 py-1 text-sm">
        <option value="">repo: any</option>
        <option :for={r <- @repos} value={r} selected={r == @repo}><%= r %></option>
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
