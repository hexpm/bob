defmodule BobWeb.CoreComponents do
  use Phoenix.Component

  attr(:flash, :map, default: %{})

  def flash_group(assigns) do
    ~H"""
    <div :for={{kind, message} <- @flash} class="rounded bg-gray-800 text-white text-sm px-3 py-2 mb-2">
      <%= kind %>: <%= message %>
    </div>
    """
  end

  attr(:rows, :list, required: true)

  slot :col, required: true do
    attr(:label, :string)
  end

  def table(assigns) do
    ~H"""
    <table class="min-w-full text-sm text-left border-collapse">
      <thead class="border-b font-medium text-gray-600">
        <tr>
          <th :for={col <- @col} class="px-3 py-2"><%= col[:label] %></th>
        </tr>
      </thead>
      <tbody>
        <tr :for={row <- @rows} class="border-b last:border-0 hover:bg-gray-50">
          <td :for={col <- @col} class="px-3 py-2 align-top"><%= render_slot(col, row) %></td>
        </tr>
      </tbody>
    </table>
    """
  end
end
