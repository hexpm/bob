defmodule Bob.Job.PurgeBuildsTest do
  use ExUnit.Case

  alias Bob.Job.PurgeBuilds

  test "exposes the runner callbacks" do
    assert PurgeBuilds.priority() == 1
    assert PurgeBuilds.weight() == 1
    assert PurgeBuilds.concurrency() == :shared
  end

  test "run/1 purges the keys, a no-op when Fastly is not configured" do
    System.delete_env("BOB_FASTLY_KEY")
    System.delete_env("BOB_FASTLY_SERVICE_BUILDS")

    assert PurgeBuilds.run("builds/otp/amd64/ubuntu-24.04/txt") == :ok
  end
end
