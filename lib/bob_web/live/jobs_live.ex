defmodule BobWeb.JobsLive do
  use BobWeb, :live_view

  @queued_page 100
  @past_page 50
  @debounce_ms 250
  @tick_ms 1000

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
        past_page: @past_page,
        loading: true,
        now: DateTime.utc_now(),
        tick_scheduled: false,
        running: [],
        queue_sizes: [],
        queue_total: 0,
        queued: [],
        past: [],
        past_total: 0
      )

    socket = if connected?(socket), do: load(socket), else: socket
    socket = if connected?(socket), do: schedule_tick(socket), else: socket

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
    {:noreply, socket |> assign(refresh_scheduled: false) |> load() |> schedule_tick()}
  end

  def handle_info(:tick, socket) do
    socket =
      socket
      |> assign(now: DateTime.utc_now(), tick_scheduled: false)
      |> schedule_tick()

    {:noreply, socket}
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
    queue_sizes =
      Bob.Queue.queue_sizes()
      |> Enum.sort_by(fn {_mod, count} -> count end, :desc)

    assign(socket,
      running: Bob.Queue.running(),
      now: DateTime.utc_now(),
      queue_sizes: queue_sizes,
      queue_total: Enum.sum(Enum.map(queue_sizes, fn {_mod, count} -> count end)),
      queued: Bob.Queue.queued_listing(@queued_page, socket.assigns.queued_offset),
      past: Bob.Queue.recent(@past_page, socket.assigns.past_offset),
      past_total: Bob.Queue.finished_count(),
      loading: false
    )
  end

  defp schedule_tick(%{assigns: %{running: [], tick_scheduled: false}} = socket), do: socket
  defp schedule_tick(%{assigns: %{tick_scheduled: true}} = socket), do: socket

  defp schedule_tick(socket) do
    Process.send_after(self(), :tick, @tick_ms)
    assign(socket, tick_scheduled: true)
  end

  defp fmt(nil), do: "—"
  defp fmt(datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")

  defp fmt_duration(nil), do: "—"

  defp fmt_duration(seconds) when seconds < 60, do: "#{seconds}s"

  defp fmt_duration(seconds) when seconds < 3600 do
    minutes = div(seconds, 60)
    seconds = rem(seconds, 60)
    "#{minutes}m #{seconds}s"
  end

  defp fmt_duration(seconds) do
    hours = div(seconds, 3600)
    minutes = div(rem(seconds, 3600), 60)
    "#{hours}h #{minutes}m"
  end

  defp elapsed(datetime, now), do: duration(datetime, now)

  defp duration(%{started_at: started_at, finished_at: finished_at}),
    do: duration(started_at, finished_at)

  defp duration(nil, _finished_at), do: nil
  defp duration(_started_at, nil), do: nil

  defp duration(started_at, finished_at) do
    NaiveDateTime.diff(to_naive(finished_at), to_naive(started_at))
    |> max(0)
  end

  defp to_naive(%DateTime{} = datetime), do: DateTime.to_naive(datetime)
  defp to_naive(%NaiveDateTime{} = datetime), do: datetime

  defp module_name(module_key), do: inspect(module_key)
  defp args_text(args), do: inspect(args)

  defp job_cat(module_key) do
    module = inspect(module_key)

    cond do
      String.contains?(module, "Docker") -> "docker"
      String.contains?(module, "Build") -> "build"
      true -> "check"
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="fade-in">
      <div class="page-head">
        <div class="page-head__main">
          <h1>Jobs</h1>
        </div>
        <div class="page-head__live">
          <span class="live-dot"></span>
          Live - updates automatically
        </div>
      </div>

      <.section
        title="Running"
        count={length(@running)}
        live={@running != []}
        icon="bolt"
        icon_class={if @running == [], do: "icon-muted", else: "icon-blue"}
      >
        <div :if={@loading} class="empty-mini">Loading jobs...</div>

        <.table :if={!@loading and @running != []} rows={@running}>
          <:col :let={_j} label="State" class="col-state">
            <div class="c-state">
              <.state_dot state="running" />
              <span class="run-label">running</span>
            </div>
          </:col>
          <:col :let={j} label="Module">
            <.module_cell cat={job_cat(j.module_key)} module={module_name(j.module_key)} />
          </:col>
          <:col :let={j} label="Args" class="col-args">
            <code class="c-args"><%= args_text(j.args) %></code>
          </:col>
          <:col :let={j} label="Started" class="col-time">
            <span class="c-time"><%= fmt(j.started_at) %></span>
          </:col>
          <:col :let={j} label="Elapsed" class="col-time">
            <span class="c-elapsed"><%= fmt_duration(elapsed(j.started_at, @now)) %></span>
          </:col>
        </.table>
        <div :if={!@loading and @running == []} class="empty-mini">Nothing running.</div>
      </.section>

      <.section title="Queue" count={@queue_total} icon="queue">
        <div :if={@loading} class="empty-mini">Loading queue...</div>

        <div :if={!@loading and @queue_sizes != []} class="qsizes">
          <div class="qsizes__label">Queued by job type</div>
          <div class="qsizes__grid">
            <div :for={{mod, count} <- @queue_sizes} class="qsize">
              <span class="qsize__l">
                <.cat_glyph cat={job_cat(mod)} size={14} />
                <code class="qsize__mod"><%= module_name(mod) %></code>
              </span>
              <span class="qsize__count"><%= count %></span>
            </div>
          </div>
        </div>
        <.table :if={!@loading and @queued != []} rows={@queued}>
          <:col :let={j} label="Module">
            <.module_cell cat={job_cat(j.module_key)} module={module_name(j.module_key)} />
          </:col>
          <:col :let={j} label="Args" class="col-args">
            <code class="c-args"><%= args_text(j.args) %></code>
          </:col>
          <:col :let={j} label="Queued" class="col-time">
            <span class="c-time"><%= fmt(j.inserted_at) %></span>
          </:col>
        </.table>
        <div :if={!@loading and @queued == []} class="empty-mini">Queue is empty.</div>
        <.pager
          :if={!@loading}
          event="queued_page"
          offset={@queued_offset}
          count={length(@queued)}
          page={@queued_page}
          unit="queued"
          total={@queue_total}
        />
      </.section>

      <.section title="Past" count={@past_total} icon="clock">
        <div :if={@loading} class="empty-mini">Loading finished jobs...</div>

        <.table :if={!@loading and @past != []} rows={@past}>
          <:col :let={j} label="State" class="col-state">
            <.state_badge state={j.state} />
          </:col>
          <:col :let={j} label="Module">
            <.module_cell cat={job_cat(j.module_key)} module={module_name(j.module_key)} />
          </:col>
          <:col :let={j} label="Args" class="col-args">
            <code class="c-args"><%= args_text(j.args) %></code>
          </:col>
          <:col :let={j} label="Duration" class="col-time">
            <span class="c-dur"><%= fmt_duration(duration(j)) %></span>
          </:col>
          <:col :let={j} label="Finished" class="col-time">
            <span class="c-time"><%= fmt(j.finished_at) %></span>
          </:col>
        </.table>
        <div :if={!@loading and @past == []} class="empty-mini">No finished jobs.</div>
        <.pager
          :if={!@loading}
          event="past_page"
          offset={@past_offset}
          count={length(@past)}
          page={@past_page}
          unit="jobs"
          total={@past_total}
        />
      </.section>
    </div>
    """
  end
end
