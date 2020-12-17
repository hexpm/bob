defmodule Bob.Job.BuildDockerErlang do
  require Logger

  def run(arch, erlang, os, os_version) do
    directory = Bob.Directory.new()
    Logger.info("Using directory #{directory}")
    Bob.Script.run({:script, "docker/erlang.sh"}, [erlang, os, os_version, arch], directory)

    Bob.RemoteQueue.docker_add("elixir-#{arch}", tag(erlang, os, os_version))
    Bob.RemoteQueue.add(Bob.Job.DockerManifest, ["erlang", [{erlang, os, os_version}]])
  end

  defp tag(erlang, os, os_version) do
    "#{erlang}-#{os}-#{os_version}"
  end

  def priority(), do: 5
  def weight(), do: 4
end
