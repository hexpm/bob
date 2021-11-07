defmodule Bob.Job.BuildElixirTest do
  use ExUnit.Case

  alias Bob.Job.BuildElixir

  describe "elixir_to_otp/1" do
    test "version tags" do
      assert BuildElixir.elixir_to_otp("v1.10.0") == ["21.3", "22.3"]
    end

    test "rc versions" do
      assert BuildElixir.elixir_to_otp("v1.8.0-rc.0") == ["20.3", "21.3", "22.3"]
    end

    test "backport" do
      assert BuildElixir.elixir_to_otp("v1.9.4") == BuildElixir.elixir_to_otp("v1.9")
    end

    test "falls back to main" do
      assert BuildElixir.elixir_to_otp("main") == BuildElixir.elixir_to_otp("some_other_tag")
    end
  end
end
