defmodule Bob.Job.DockerManifest do
  require Logger

  def run(kind, key) do
    directory = Bob.Directory.new()
    Logger.info("Using directory #{directory}")
    tag = key_to_tag(kind, key)
    archs = get_archs(kind, tag)

    if archs == [] do
      :ok
    else
      Bob.Script.run(
        {:script, "docker/manifest.sh"},
        [kind, tag] ++ archs,
        directory
      )

      Bob.RemoteQueue.docker_add("hexpm/#{kind}", tag)
    end
  end

  def key_to_tag("erlang", {erlang, os, os_version}) do
    "#{erlang}-#{os}-#{os_version}"
  end

  def key_to_tag("elixir", {elixir, erlang, os, os_version}) do
    "#{elixir}-erlang-#{erlang}-#{os}-#{os_version}"
  end

  def priority(), do: 4
  def weight(), do: 4

  def get_archs(kind, tag) do
    ["amd64", "arm64"]
    |> Enum.map(&{&1, Bob.DockerHub.fetch_tag("hexpm/#{kind}-#{&1}", tag)})
    |> Enum.flat_map(fn
      {_arch, nil} -> []
      {arch, _} -> [arch]
    end)
  end
end
