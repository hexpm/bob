defmodule Bob.FastlyTest do
  use ExUnit.Case

  describe "purge_builds/1" do
    test "is a no-op returning :ok when Fastly is not configured" do
      System.delete_env("BOB_FASTLY_KEY")
      System.delete_env("BOB_FASTLY_SERVICE_BUILDS")

      assert Bob.Fastly.purge_builds("builds/otp/amd64/ubuntu-24.04/txt") == :ok
    end
  end
end
