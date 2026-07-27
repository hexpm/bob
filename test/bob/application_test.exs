defmodule Bob.ApplicationTest do
  use ExUnit.Case, async: true

  test "PromEx starts before the repo so it sees the repo's init telemetry" do
    children = Bob.Application.children()

    assert Enum.find_index(children, &(&1 == Bob.PromEx)) <
             Enum.find_index(children, &(&1 == Bob.Repo))
  end
end
