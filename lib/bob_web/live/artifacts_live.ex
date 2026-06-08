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

  @impl true
  def render(assigns) do
    ~H"""
    <h2 class="text-lg font-semibold mb-4">Build artifacts</h2>

    <form phx-change="search" phx-submit="search" class="flex flex-wrap gap-2 mb-4">
      <input
        type="text"
        name="query"
        value={@query}
        placeholder="Search name or ref…"
        class="border rounded px-2 py-1 text-sm"
      />
      <select name="kind" class="border rounded px-2 py-1 text-sm">
        <option value="">kind: any</option>
        <option :for={k <- @kinds} value={k} selected={k == @kind}><%= k %></option>
      </select>
      <select name="arch" class="border rounded px-2 py-1 text-sm">
        <option value="">arch: any</option>
        <option :for={a <- @arches} value={a} selected={a == @arch}><%= a %></option>
      </select>
      <select name="os" class="border rounded px-2 py-1 text-sm">
        <option value="">os: any</option>
        <option :for={o <- @oses} value={o} selected={o == @os}><%= o %></option>
      </select>
    </form>

    <.table :if={@results != []} rows={@results}>
      <:col :let={a} label="kind"><%= a.kind %></:col>
      <:col :let={a} label="arch"><%= a.arch %></:col>
      <:col :let={a} label="os"><%= a.os %></:col>
      <:col :let={a} label="name"><%= a.name %></:col>
      <:col :let={a} label="ref"><code><%= a.ref %></code></:col>
      <:col :let={a} label="sha256"><code><%= a.sha256 %></code></:col>
      <:col :let={a} label="built"><%= fmt(a.built_at) %></:col>
    </.table>
    <p :if={@results == []} class="text-sm text-gray-500">No matching artifacts.</p>

    <div class="flex gap-2 mt-3 text-sm">
      <button phx-click="page" phx-value-dir="prev" disabled={@offset == 0} class="px-2 py-1 border rounded disabled:opacity-40">Prev</button>
      <button phx-click="page" phx-value-dir="next" disabled={length(@results) < @page} class="px-2 py-1 border rounded disabled:opacity-40">Next</button>
    </div>
    """
  end
end
