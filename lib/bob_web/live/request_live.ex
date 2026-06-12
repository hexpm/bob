defmodule BobWeb.RequestLive do
  use BobWeb, :live_view

  alias Bob.BuildRequests
  alias Bob.BuildRequests.BuildRequest
  alias Bob.Job.DockerChecker

  @options_ttl 10 * 60

  @impl true
  def mount(_params, _session, socket) do
    builds = DockerChecker.builds()

    oses =
      builds
      |> Enum.filter(fn {_os, os_versions} -> os_versions != [] end)
      |> Enum.map(fn {os, _os_versions} -> os end)
      |> Enum.sort()

    socket =
      socket
      |> assign(
        builds: builds,
        oses: oses,
        erlang_versions: nil,
        elixir_builds: nil,
        kind: "erlang",
        os: "",
        os_version: "",
        erlang: "",
        elixir: "",
        my_requests: my_requests(socket)
      )

    socket =
      if connected?(socket) do
        start_async(socket, :options, fn -> load_options() end)
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def handle_async(:options, {:ok, {erlang_versions, elixir_builds}}, socket) do
    {:noreply, assign(socket, erlang_versions: erlang_versions, elixir_builds: elixir_builds)}
  end

  def handle_async(:options, {:exit, _reason}, socket) do
    {:noreply,
     replace_flash(socket, :error, "Loading versions failed, reload the page to retry.")}
  end

  @impl true
  def handle_event("validate", params, socket) do
    {:noreply, socket |> apply_form(params) |> clear_flash()}
  end

  def handle_event("request", params, socket) do
    socket = apply_form(socket, params)
    %{kind: kind, os: os, os_version: os_version, erlang: erlang} = socket.assigns

    cond do
      socket.assigns.erlang_versions == nil ->
        {:noreply,
         replace_flash(socket, :error, "Versions are still loading, try again shortly.")}

      os == "" or os_version == "" or erlang == "" or
          (kind == "elixir" and socket.assigns.elixir == "") ->
        {:noreply, replace_flash(socket, :error, "Select a value for every field.")}

      true ->
        {:noreply, submit(socket)}
    end
  end

  # Selected values are only kept when they appear in the option lists, which
  # are derived from real refs and builds and already encode the build rules.
  # Submitted values are therefore valid by construction, also when the params
  # bypass the rendered dropdowns.
  defp apply_form(socket, params) do
    kind = if params["kind"] in ~w(erlang elixir), do: params["kind"], else: "erlang"
    os = keep_member(params["os"], socket.assigns.oses)
    os_version = keep_member(params["os_version"], Map.get(socket.assigns.builds, os, []))

    assigns = %{socket.assigns | kind: kind, os: os, os_version: os_version}
    erlang = keep_member(params["erlang"], erlang_options(assigns))
    assigns = %{assigns | erlang: erlang}

    elixir =
      if kind == "elixir" do
        keep_member(params["elixir"], elixir_options(assigns))
      else
        ""
      end

    assign(socket, kind: kind, os: os, os_version: os_version, elixir: elixir, erlang: erlang)
  end

  defp keep_member(value, options) do
    if value in options, do: value, else: ""
  end

  defp submit(socket) do
    attrs = %{
      username: socket.assigns.current_user["username"],
      kind: socket.assigns.kind,
      elixir: selected_elixir(socket.assigns),
      erlang: socket.assigns.erlang,
      os: socket.assigns.os,
      os_version: socket.assigns.os_version
    }

    case BuildRequests.submit(attrs) do
      {:ok, %BuildRequest{}} ->
        socket
        |> assign(my_requests: my_requests(socket))
        |> replace_flash(:info, "Build queued, follow the progress on the jobs dashboard.")

      {:ok, :already_built} ->
        replace_flash(socket, :info, "This image is already built, find it under Docker tags.")

      {:error, :rate_limited} ->
        replace_flash(
          socket,
          :error,
          "You reached the limit of #{BuildRequests.hourly_build_limit()} requested builds " <>
            "per hour, try again later."
        )

      {:error, :invalid_combo} ->
        replace_flash(socket, :error, "This combination is not supported by the build rules.")
    end
  end

  defp replace_flash(socket, kind, message) do
    socket
    |> clear_flash()
    |> put_flash(kind, message)
  end

  defp my_requests(socket) do
    BuildRequests.recent_for_user(socket.assigns.current_user["username"])
  end

  defp load_options() do
    erlang_versions =
      Bob.Cache.fetch(:erlang_versions, @options_ttl, &DockerChecker.erlang_versions/0)

    elixir_builds = Bob.Cache.fetch(:elixir_builds, @options_ttl, &DockerChecker.elixir_builds/0)

    {erlang_versions, elixir_builds}
  end

  defp erlang_options(%{erlang_versions: nil}), do: []
  defp erlang_options(%{os: ""}), do: []
  defp erlang_options(%{os_version: ""}), do: []

  defp erlang_options(assigns) do
    %{erlang_versions: versions, os: os, os_version: os_version} = assigns

    Enum.filter(versions, &DockerChecker.valid_erlang_build?(&1, os, os_version))
  end

  defp elixir_options(%{elixir_builds: nil}), do: []
  defp elixir_options(%{erlang: ""}), do: []

  defp elixir_options(%{
         elixir_builds: elixir_builds,
         erlang: erlang,
         os: os,
         os_version: os_version
       }) do
    otp_major = otp_major(erlang)

    elixir_builds
    |> Enum.filter(fn
      {"v" <> elixir, ^otp_major} ->
        DockerChecker.valid_elixir_build?(elixir, otp_major, erlang, os, os_version)

      _other ->
        false
    end)
    |> Enum.map(fn {"v" <> elixir, _otp_major} -> elixir end)
    |> Enum.uniq()
  end

  defp otp_major(erlang), do: erlang |> String.split(".") |> hd()

  defp selected_elixir(%{kind: "elixir", elixir: elixir}), do: elixir
  defp selected_elixir(_assigns), do: nil

  # The erlang base image gets built first when it is missing; surface that so
  # users know why their elixir tag appears only after a later cycle.
  defp staged_notice?(assigns) do
    assigns.kind == "elixir" and assigns.erlang != "" and assigns.os_version != "" and
      not erlang_base_present?(assigns)
  end

  defp erlang_base_present?(assigns) do
    tag = "#{assigns.erlang}-#{assigns.os}-#{assigns.os_version}"

    Enum.all?(DockerChecker.archs(), fn arch ->
      "hexpm/erlang-#{arch}"
      |> Bob.Artifacts.docker_tags_present([tag])
      |> MapSet.member?(tag)
    end)
  end

  defp fmt(datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")

  defp target(%{kind: "erlang"} = request) do
    "#{request.erlang}-#{request.os}-#{request.os_version}"
  end

  defp target(%{kind: "elixir"} = request) do
    "#{request.elixir}-erlang-#{request.erlang}-#{request.os}-#{request.os_version}"
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="fade-in">
      <div class="page-head">
        <div class="page-head__main">
          <h1>Request a build</h1>
        </div>
      </div>

      <section class="sec">
        <p class="req-intro">
          Bob automatically builds Docker images for the latest patch release of every
          Erlang and Elixir version. Need an older patch version? Request it here and it
          is built for both architectures, including the multi-arch manifest.
        </p>

        <form phx-change="validate" phx-submit="request" class="filter-bar filter-bar--wrap">
          <.form_select name="kind" label="image" value={@kind} options={~w(erlang elixir)} />
          <.form_select name="os" label="os" value={@os} options={@oses} prompt="Select OS" />
          <.form_select
            name="os_version"
            label="os version"
            value={@os_version}
            options={Map.get(@builds, @os, [])}
            disabled={@os == ""}
            prompt="Select OS version"
          />
          <.form_select
            name="erlang"
            label="erlang"
            value={@erlang}
            options={erlang_options(assigns)}
            disabled={@erlang_versions == nil or @os_version == ""}
            prompt="Select Erlang"
          />
          <.form_select
            :if={@kind == "elixir"}
            name="elixir"
            label="elixir"
            value={@elixir}
            options={elixir_options(assigns)}
            disabled={@elixir_builds == nil or @erlang == ""}
            prompt="Select Elixir"
          />
          <button class="pg-btn" type="submit">Request build</button>
        </form>

        <div :if={@erlang_versions == nil} class="empty-mini">Loading versions...</div>

        <div :if={@erlang_versions != nil && staged_notice?(assigns)} class="empty-mini">
          The Erlang base image for this combination does not exist yet, so it is built
          first and the Elixir image follows automatically afterwards.
        </div>
      </section>

      <.section :if={@my_requests != []} title="Your recent requests" icon="clock">
        <.table rows={@my_requests} class="jt--req">
          <:col :let={request} label="image">
            <%= request.kind %>
          </:col>
          <:col :let={request} label="tag">
            <code class="dk-tag-code" title={target(request)}><%= target(request) %></code>
          </:col>
          <:col :let={request} label="state">
            <%= request.state %>
          </:col>
          <:col :let={request} label="requested">
            <span class="c-time"><%= fmt(request.inserted_at) %></span>
          </:col>
        </.table>
      </.section>
    </div>
    """
  end

  attr(:name, :string, required: true)
  attr(:label, :string, required: true)
  attr(:value, :string, default: "")
  attr(:options, :list, required: true)
  attr(:disabled, :boolean, default: false)
  attr(:prompt, :string, default: nil)

  defp form_select(assigns) do
    ~H"""
    <label class={["fsel", @disabled && "fsel--off"]}>
      <span class="fsel__label"><%= @label %>:</span>
      <select name={@name} disabled={@disabled}>
        <option :if={@prompt} value="" disabled selected={@value == ""} hidden>
          <%= @prompt %>
        </option>
        <option :for={option <- @options} value={option} selected={option == @value}>
          <%= option %>
        </option>
      </select>
      <.icon name="chevD" size={13} />
    </label>
    """
  end
end
