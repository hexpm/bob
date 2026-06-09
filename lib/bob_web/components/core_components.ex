defmodule BobWeb.CoreComponents do
  use Phoenix.Component

  attr(:flash, :map, default: %{})

  def flash_group(assigns) do
    ~H"""
    <div :for={{kind, message} <- @flash} class="flash">
      <%= kind %>: <%= message %>
    </div>
    """
  end

  attr(:name, :string, required: true)
  attr(:size, :integer, default: 16)
  attr(:class, :any, default: nil)

  def icon(assigns) do
    assigns = assign(assigns, :paths, icon_paths(assigns.name))

    ~H"""
    <svg
      class={@class}
      width={@size}
      height={@size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="1.7"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
    >
      <path :for={path <- @paths} d={path} />
    </svg>
    """
  end

  attr(:title, :string, required: true)
  attr(:count, :integer, default: nil)
  attr(:icon, :string, default: nil)
  attr(:icon_class, :string, default: nil)
  attr(:live, :boolean, default: false)
  slot(:inner_block, required: true)

  def section(assigns) do
    ~H"""
    <section class="sec">
      <div class="sec__head">
        <div class="sec__title">
          <.icon :if={@icon} name={@icon} class={@icon_class} />
          <%= @title %>
        </div>
        <span :if={!is_nil(@count)} class={["sec__count", @live && "sec__count--live"]}>
          <%= @count %>
        </span>
      </div>
      <%= render_slot(@inner_block) %>
    </section>
    """
  end

  attr(:rows, :list, required: true)
  attr(:class, :string, default: nil)

  slot :col, required: true do
    attr(:label, :string)
    attr(:class, :string)
  end

  def table(assigns) do
    ~H"""
    <div class="tbl-wrap">
      <table class={["jt", @class]}>
        <thead>
          <tr>
            <th :for={col <- @col} class={col[:class]}><%= col[:label] %></th>
          </tr>
        </thead>
        <tbody>
          <tr :for={row <- @rows} class={row_class(row)}>
            <td :for={col <- @col} class={col[:class]}><%= render_slot(col, row) %></td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  attr(:event, :string, required: true)
  attr(:offset, :integer, required: true)
  attr(:count, :integer, required: true)
  attr(:page, :integer, required: true)
  attr(:unit, :string, default: nil)
  attr(:total, :integer, default: nil)

  def pager(assigns) do
    assigns =
      assigns
      |> assign(:from, if(assigns.count == 0, do: 0, else: assigns.offset + 1))
      |> assign(:to, assigns.offset + assigns.count)
      |> assign(:range_unit, format_unit(assigns.unit, assigns.count))
      |> assign(:next_disabled, next_disabled?(assigns))

    ~H"""
    <div class="pager">
      <div class="pager__info">
        <span :if={@count == 0}>Nothing to show</span>
        <span :if={@count > 0}>
          Showing <b><%= @from %></b>-<b><%= @to %></b><%= if @range_unit,
            do: " " <> @range_unit %>
          <%= total_text(@total, @unit) %>
        </span>
      </div>
      <div class="pager__btns">
        <button class="pg-btn" phx-click={@event} phx-value-dir="prev" disabled={@offset == 0}>
          <.icon name="chevL" size={14} /> Prev
        </button>
        <button class="pg-btn" phx-click={@event} phx-value-dir="next" disabled={@next_disabled}>
          Next <.icon name="chevR" size={14} />
        </button>
      </div>
    </div>
    """
  end

  def format_count(count) do
    count
    |> Integer.to_string()
    |> String.replace(~r/\B(?=(\d{3})+(?!\d))/, ",")
  end

  def format_unit(nil, _count), do: nil
  def format_unit(unit, 1), do: singular_unit(unit)
  def format_unit(unit, _count), do: unit

  defp next_disabled?(%{count: count, page: page}) when count < page, do: true

  defp next_disabled?(%{total: total, offset: offset, count: count}) when not is_nil(total),
    do: offset + count >= total

  defp next_disabled?(_assigns), do: false

  defp total_text(nil, _unit), do: nil

  defp total_text(total, unit) do
    unit = if unit, do: " " <> format_unit(unit, total), else: ""
    " of #{format_count(total)}#{unit}"
  end

  defp singular_unit(unit) do
    if String.ends_with?(unit, "s") do
      String.trim_trailing(unit, "s")
    else
      unit
    end
  end

  attr(:state, :any, required: true)

  def state_badge(assigns) do
    assigns = assign(assigns, :state_name, to_string(assigns.state))

    ~H"""
    <span class={["badge", state_badge_class(@state_name)]}>
      <span class="badge__dot"></span>
      <%= @state_name %>
    </span>
    """
  end

  attr(:state, :any, required: true)

  def state_dot(assigns) do
    assigns = assign(assigns, :state_name, to_string(assigns.state))

    ~H"""
    <span class={["state-dot", "state-dot--#{@state_name}", @state_name == "running" && "state-dot--pulse"]}>
    </span>
    """
  end

  attr(:cat, :string, required: true)
  attr(:size, :integer, default: 15)

  def cat_glyph(assigns) do
    assigns = assign(assigns, :icon, cat_icon(assigns.cat))

    ~H"""
    <span class={["cat-glyph", "cat-glyph--#{@cat}"]}>
      <.icon name={@icon} size={@size} />
    </span>
    """
  end

  attr(:cat, :string, required: true)
  attr(:module, :string, required: true)

  def module_cell(assigns) do
    ~H"""
    <div class="c-mod">
      <.cat_glyph cat={@cat} />
      <span class="mod-name"><%= @module %></span>
    </div>
    """
  end

  attr(:name, :string, required: true)
  attr(:value, :string, default: "")
  attr(:placeholder, :string, required: true)

  def search_box(assigns) do
    ~H"""
    <div class="search-wrap">
      <div class="search-box">
        <.icon name="search" />
        <input type="text" name={@name} value={@value} placeholder={@placeholder} />
      </div>
    </div>
    """
  end

  attr(:name, :string, required: true)
  attr(:label, :string, required: true)
  attr(:value, :string, default: "")
  attr(:options, :list, required: true)
  attr(:disabled, :boolean, default: false)

  def filter_select(assigns) do
    ~H"""
    <label class={["fsel", @disabled && "fsel--off"]}>
      <span class="fsel__label"><%= @label %>:</span>
      <select name={@name} disabled={@disabled}>
        <option value="">any</option>
        <option :for={option <- @options} value={option} selected={option == @value}><%= option %></option>
      </select>
      <.icon name="chevD" size={13} />
    </label>
    """
  end

  attr(:name, :string, required: true)
  attr(:value, :string, default: "")
  attr(:placeholder, :string, required: true)
  attr(:disabled, :boolean, default: false)

  def filter_text(assigns) do
    ~H"""
    <div class={["finput", @disabled && "finput--off"]}>
      <input
        type="text"
        name={@name}
        value={@value}
        placeholder={@placeholder}
        disabled={@disabled}
      />
    </div>
    """
  end

  defp icon_paths("search"), do: ["M21 21l-4.34-4.34M19 11a8 8 0 11-16 0 8 8 0 0116 0z"]
  defp icon_paths("check"), do: ["M4.5 12.75l6 6 9-13.5"]
  defp icon_paths("x"), do: ["M6 18L18 6M6 6l12 12"]
  defp icon_paths("bolt"), do: ["M3.75 13.5l10.5-11.25-1.5 9h6.75L9 22.5l1.5-9h-6.75z"]
  defp icon_paths("clock"), do: ["M12 6v6l4 2m6-2a9 9 0 11-18 0 9 9 0 0118 0z"]
  defp icon_paths("menu"), do: icon_paths("queue")
  defp icon_paths("queue"), do: ["M3.75 6.75h16.5M3.75 12h16.5M3.75 17.25h16.5"]

  defp icon_paths("box"),
    do: [
      "M21 7.5l-9-5.25L3 7.5m18 0l-9 5.25m9-5.25v9l-9 5.25M3 7.5l9 5.25M3 7.5v9l9 5.25m0-9v9"
    ]

  defp icon_paths("cube"), do: icon_paths("box")

  defp icon_paths("docker"),
    do: [
      "M3 13.5h18M5.25 13.5V9.75h3v3.75m1.5 0V6.75h3v6.75m1.5 0V9.75h3v3.75M3 13.5c0 4 3 6.75 7.5 6.75 6 0 9-3.75 9.75-6.75"
    ]

  defp icon_paths("refresh"),
    do: [
      "M16.023 9.348h4.992V4.356M3.75 9.348a8.25 8.25 0 0113.803-3.7L20.25 8.4M3.985 14.652a8.25 8.25 0 0013.803 3.7L20.25 15.6m0 4.8v-4.99h-4.992"
    ]

  defp icon_paths("chevL"), do: ["M15.75 19.5L8.25 12l7.5-7.5"]
  defp icon_paths("chevR"), do: ["M8.25 4.5l7.5 7.5-7.5 7.5"]
  defp icon_paths("chevD"), do: ["M19.5 8.25l-7.5 7.5-7.5-7.5"]

  defp icon_paths("external"),
    do: [
      "M13.5 6H5.25A2.25 2.25 0 003 8.25v10.5A2.25 2.25 0 005.25 21h10.5A2.25 2.25 0 0018 18.75V10.5m-10.5 6L21 3m0 0h-5.25M21 3v5.25"
    ]

  defp icon_paths(_name), do: []

  defp row_class(%{state: "failed"}), do: "row--failed"
  defp row_class(_row), do: nil

  defp state_badge_class("done"), do: "badge--success"
  defp state_badge_class("failed"), do: "badge--danger"
  defp state_badge_class("running"), do: "badge--running"
  defp state_badge_class(_state), do: "badge--neutral"

  defp cat_icon("build"), do: "cube"
  defp cat_icon("docker"), do: "docker"
  defp cat_icon(_cat), do: "refresh"
end
