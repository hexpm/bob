defmodule Bob.Job.DockerManifest do
  require Logger

  def run(kind, key, archs) do
    directory = Bob.Directory.new()
    Logger.info("Using directory #{directory}")
    tag = key_to_tag(kind, key)

    Bob.Script.run(
      {:script, "docker/manifest.sh"},
      [kind, tag] ++ archs,
      directory
    )
  end

  defp key_to_tag("erlang", {erlang, os, os_version}) do
    "#{erlang}-#{os}-#{os_version}"
  end

  defp key_to_tag("elixir", {elixir, erlang, os, os_version}) do
    "#{elixir}-erlang-#{erlang}-#{os}-#{os_version}"
  end

  def priority(), do: 4
  def weight(), do: 1
end
