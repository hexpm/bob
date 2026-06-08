defmodule BobWeb.JobsLive do
  use BobWeb, :live_view

  @queued_page 100
  @past_page 50
  @debounce_ms 250

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Bob.PubSub, "jobs")

    socket =
      socket
      |> assign(
        queued_offset: 0,
        past_offset: 0,
        refresh_scheduled: false,
        queued_page: @queued_page,
        past_page: @past_page
      )
      |> load()

    {:ok, socket}
  end

  @impl true
  def handle_info(:jobs_changed, %{assigns: %{refresh_scheduled: true}} = socket) do
    {:noreply, socket}
  end

  def handle_info(:jobs_changed, socket) do
    Process.send_after(self(), :refresh, @debounce_ms)
    {:noreply, assign(socket, refresh_scheduled: true)}
  end

  def handle_info(:refresh, socket) do
    {:noreply, socket |> assign(refresh_scheduled: false) |> load()}
  end

  @impl true
  def handle_event("queued_page", %{"dir" => dir}, socket) do
    offset = max(socket.assigns.queued_offset + step(dir, @queued_page), 0)
    {:noreply, socket |> assign(queued_offset: offset) |> load()}
  end

  def handle_event("past_page", %{"dir" => dir}, socket) do
    offset = max(socket.assigns.past_offset + step(dir, @past_page), 0)
    {:noreply, socket |> assign(past_offset: offset) |> load()}
  end

  defp step("next", page), do: page
  defp step("prev", page), do: -page

  defp load(socket) do
    assign(socket,
      running: Bob.Queue.running(),
      queue_sizes: Enum.sort(Bob.Queue.queue_sizes()),
      queued: Bob.Queue.queued_listing(@queued_page, socket.assigns.queued_offset),
      past: Bob.Queue.recent(@past_page, socket.assigns.past_offset)
    )
  end

  defp fmt(nil), do: "—"
  defp fmt(datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-10">
      <section>
        <h2 class="text-lg font-semibold mb-2">Running (<%= length(@running) %>)</h2>
        <.table :if={@running != []} rows={@running}>
          <:col :let={j} label="Module"><code><%= inspect(j.module_key) %></code></:col>
          <:col :let={j} label="Args"><code><%= inspect(j.args) %></code></:col>
          <:col :let={j} label="Started"><%= fmt(j.started_at) %></:col>
        </.table>
        <p :if={@running == []} class="text-sm text-gray-500">Nothing running.</p>
      </section>

      <section>
        <h2 class="text-lg font-semibold mb-2">Queue</h2>
        <ul :if={@queue_sizes != []} class="text-sm mb-3 space-y-1">
          <li :for={{mod, count} <- @queue_sizes}>
            <code><%= inspect(mod) %></code> — <%= count %>
          </li>
        </ul>
        <.table :if={@queued != []} rows={@queued}>
          <:col :let={j} label="Module"><code><%= inspect(j.module_key) %></code></:col>
          <:col :let={j} label="Args"><code><%= inspect(j.args) %></code></:col>
          <:col :let={j} label="Queued"><%= fmt(j.inserted_at) %></:col>
        </.table>
        <p :if={@queued == []} class="text-sm text-gray-500">Queue is empty.</p>
        <.pager event="queued_page" offset={@queued_offset} count={length(@queued)} page={@queued_page} />
      </section>

      <section>
        <h2 class="text-lg font-semibold mb-2">Past</h2>
        <.table :if={@past != []} rows={@past}>
          <:col :let={j} label="State"><%= j.state %></:col>
          <:col :let={j} label="Module"><code><%= inspect(j.module_key) %></code></:col>
          <:col :let={j} label="Args"><code><%= inspect(j.args) %></code></:col>
          <:col :let={j} label="Finished"><%= fmt(j.finished_at) %></:col>
        </.table>
        <p :if={@past == []} class="text-sm text-gray-500">No finished jobs.</p>
        <.pager event="past_page" offset={@past_offset} count={length(@past)} page={@past_page} />
      </section>
    </div>
    """
  end

  attr(:event, :string, required: true)
  attr(:offset, :integer, required: true)
  attr(:count, :integer, required: true)
  attr(:page, :integer, required: true)

  defp pager(assigns) do
    ~H"""
    <div class="flex gap-2 mt-2 text-sm">
      <button
        phx-click={@event}
        phx-value-dir="prev"
        disabled={@offset == 0}
        class="px-2 py-1 border rounded disabled:opacity-40"
      >
        Prev
      </button>
      <button
        phx-click={@event}
        phx-value-dir="next"
        disabled={@count < @page}
        class="px-2 py-1 border rounded disabled:opacity-40"
      >
        Next
      </button>
    </div>
    """
  end
end
