defmodule BobWeb.Layouts do
  use BobWeb, :html

  def nav_class(current_path, target_path) do
    [
      "bob-nav__tab",
      nav_active?(current_path, target_path) && "bob-nav__tab--active"
    ]
  end

  def menu_class(current_path, target_path) do
    [
      "bob-menu__item",
      nav_active?(current_path, target_path) && "bob-menu__item--active"
    ]
  end

  defp nav_active?("/", "/"), do: true
  defp nav_active?("/artifacts", "/artifacts"), do: true
  defp nav_active?("/docker", "/docker"), do: true
  defp nav_active?(_current_path, _target_path), do: false

  embed_templates("layouts/*")
end
