defmodule Bob.Job.BuildDockerElixir do
  require Logger

  def run(arch, elixir, erlang, os, os_version) do
    directory = Bob.Directory.new()
    Logger.info("Using directory #{directory}")

    Bob.Script.run(
      {:script, "docker/elixir.sh"},
      [elixir, erlang, os, os_version, arch],
      directory
    )
  end

  def priority(), do: 4
  def weight(), do: 1
end
