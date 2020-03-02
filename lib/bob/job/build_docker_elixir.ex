defmodule Bob.Job.BuildDockerElixir do
  require Logger

  def run([elixir, erlang, os, os_version]) do
    directory = Bob.Directory.new()
    Logger.info("Using directory #{directory}")

    Bob.Script.run(
      {:script, "docker/elixir.sh"},
      [elixir, erlang, os, os_version],
      directory
    )
  end
end
