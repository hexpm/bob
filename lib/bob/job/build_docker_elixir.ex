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

    Bob.RemoteQueue.docker_add("elixir-#{arch}", tag(elixir, erlang, os, os_version))
    Bob.RemoteQueue.add(Bob.Job.DockerManifest, ["elixir", [{elixir, erlang, os, os_version}]])
  end

  defp tag(elixir, erlang, os, os_version) do
    "#{elixir}-erlang-#{erlang}-#{os}-#{os_version}"
  end

  def priority(), do: 4
  def weight(), do: 1
end
