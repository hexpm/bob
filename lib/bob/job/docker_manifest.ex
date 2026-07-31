defmodule Bob.Job.DockerManifest do
  require Logger

  def run(kind, key) do
    directory = Bob.Directory.new()
    Logger.info("Using directory #{directory}")
    tag = key_to_tag(kind, key)

    case get_archs(kind, tag) do
      {:ok, []} ->
        :ok

      {:ok, archs} ->
        Bob.Script.run(
          {:script, "docker/manifest.sh"},
          [kind, tag] ++ archs,
          directory
        )

        Bob.RemoteQueue.docker_add("hexpm/#{kind}", tag, archs)

      {:unreadable, arch} ->
        Logger.warning(
          "MANIFEST hexpm/#{kind}:#{tag} left alone, hexpm/#{kind}-#{arch}:#{tag} did not read"
        )

        :ok
    end
  end

  def priority(), do: 4
  def weight(), do: 2
  def concurrency(), do: __MODULE__

  def key_to_tag("erlang", {erlang, os, os_version}) do
    "#{erlang}-#{os}-#{os_version}"
  end

  def key_to_tag("elixir", {elixir, erlang, os, os_version}) do
    "#{elixir}-erlang-#{erlang}-#{os}-#{os_version}"
  end

  @doc """
  The archs to publish the manifest from.

  A tag Docker Hub reports as gone is absent, and the manifest is published from
  whatever else is there — that is how a tag gets a manifest while its second
  arch is still building. A response that carries no usable image data says
  nothing about the tag, and publishing on it would rewrite a multi-arch
  manifest as whatever happened to be legible.
  """
  def get_archs(kind, tag, fetch \\ &Bob.DockerHub.fetch_tag/2) do
    ["amd64", "arm64"]
    |> Enum.reduce_while([], fn arch, acc ->
      case fetch.("hexpm/#{kind}-#{arch}", tag) do
        {:ok, _tag} -> {:cont, [arch | acc]}
        :not_found -> {:cont, acc}
        :unreadable -> {:halt, {:unreadable, arch}}
      end
    end)
    |> case do
      {:unreadable, arch} -> {:unreadable, arch}
      archs -> {:ok, Enum.reverse(archs)}
    end
  end
end
