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

    Bob.RemoteQueue.docker_add("hexpm/elixir-#{arch}", tag(elixir, erlang, os, os_version), [arch])

    Bob.RemoteQueue.add(Bob.Job.DockerManifest, ["elixir", {elixir, erlang, os, os_version}])
  end

  defp tag(elixir, erlang, os, os_version) do
    "#{elixir}-erlang-#{erlang}-#{os}-#{os_version}"
  end

  # The image can only be built once both releases are out, so it is as new as
  # the newer of the two.
  def released_at([_arch, elixir, erlang, _os, _os_version]) do
    [
      Bob.Job.DockerChecker.elixir_released_at(elixir),
      Bob.Job.DockerChecker.erlang_released_at(erlang)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.max(DateTime, fn -> nil end)
  end

  def priority(), do: 4
  def weight(), do: 2
  def concurrency(), do: :shared
end
