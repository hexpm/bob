defmodule BobWeb.LayoutsTest do
  use ExUnit.Case, async: true

  alias BobWeb.Layouts

  describe "nav_class/2" do
    test "marks the tab active when the path matches its target" do
      for path <- ["/", "/artifacts", "/docker", "/request"] do
        assert "bob-nav__tab--active" in Layouts.nav_class(path, path)
      end
    end

    test "does not mark other tabs active" do
      refute "bob-nav__tab--active" in Layouts.nav_class("/request", "/docker")
    end
  end

  describe "menu_class/2" do
    test "marks the menu item active when the path matches its target" do
      assert "bob-menu__item--active" in Layouts.menu_class("/request", "/request")
    end

    test "does not mark other menu items active" do
      refute "bob-menu__item--active" in Layouts.menu_class("/request", "/")
    end
  end
end
