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

  # The newer of the Elixir and OTP releases is when the image first became
  # possible, so it ranks first; the base image only breaks ties.
  def release_dates([_arch, elixir, erlang, os, os_version]) do
    [newer, older] =
      [
        Bob.Job.DockerChecker.elixir_released_at(elixir),
        Bob.Job.DockerChecker.erlang_released_at(erlang)
      ]
      |> Enum.sort_by(&if(&1, do: DateTime.to_unix(&1), else: 0), :desc)

    [newer, older, Bob.Job.DockerChecker.base_image_released_at(os, os_version)]
  end

  def priority(), do: 4
  def weight(), do: 2
  def concurrency(), do: :shared
end
