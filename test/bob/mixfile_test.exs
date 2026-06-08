defmodule Bob.MixfileTest do
  use ExUnit.Case, async: true

  test "configures Phoenix code reloader as a Mix listener" do
    assert Phoenix.CodeReloader in Keyword.fetch!(Bob.Mixfile.project(), :listeners)
  end
end
