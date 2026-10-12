defmodule Bob.PromExTest do
  # These tests change the node's role in the application environment.
  use ExUnit.Case, async: false

  setup do
    master? = Application.get_env(:bob, :master?)
    on_exit(fn -> Application.put_env(:bob, :master?, master?) end)
    :ok
  end

  defp plugin_modules() do
    Enum.map(Bob.PromEx.plugins(), fn
      {module, _opts} -> module
      module -> module
    end)
  end

  test "reports HTTP metrics without client-chosen labels on the master and the agents" do
    for master? <- [true, false] do
      Application.put_env(:bob, :master?, master?)

      assert Bob.PromEx.Plugins.Phoenix in plugin_modules()
      refute PromEx.Plugins.Phoenix in plugin_modules()
    end
  end
end
