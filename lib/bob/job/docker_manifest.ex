defmodule Bob.Job.DockerManifest do
  require Logger

  @archs ["amd64", "arm64"]

  def run(kind, key) do
    tag = key_to_tag(kind, key)

    case get_archs(kind, tag) do
      {:ok, []} ->
        :ok

      {:ok, sources} ->
        if publish?(kind, tag, sources) do
          directory = Bob.Directory.new()
          Logger.info("Using directory #{directory}")
          archs = Enum.map(sources, fn {arch, _built_at} -> arch end)

          Bob.Script.run(
            {:script, "docker/manifest.sh"},
            [kind, tag] ++ archs,
            directory
          )

          Bob.RemoteQueue.docker_add("hexpm/#{kind}", tag, archs)
        else
          :ok
        end

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
  Whether a manifest should be built from `sources`, each an `{arch, built_at}`.

  A manifest spans the arches it was built from, and those per-arch tags are
  deleted once they are 30 days old, so building from what survives would drop
  the rest. Anything that would lose an arch is left alone.

  Beyond that it is built when it would gain an arch, or when a source has been
  pushed since it was last built — the same tag can be re-pushed under a new
  digest, and the manifest has to follow. A manifest already spanning these
  arches and newer than all of them is left as it is rather than rewritten as
  itself.
  """
  def publish?(kind, tag, sources, fetch \\ &Bob.DockerHub.fetch_tag/2) do
    case fetch.("hexpm/#{kind}", tag) do
      :not_found ->
        true

      :unreadable ->
        false

      {:ok, {_tag, published, built_at}} ->
        archs = MapSet.new(sources, fn {arch, _at} -> arch end)
        published = MapSet.new(published)

        cond do
          not MapSet.subset?(published, archs) -> false
          not MapSet.equal?(published, archs) -> true
          true -> Enum.any?(sources, fn {_arch, at} -> DateTime.compare(at, built_at) == :gt end)
        end
    end
  end

  @doc """
  The `{arch, built_at}` sources to build the manifest from.

  A tag Docker Hub reports as gone is absent. A response that carries no usable
  image data says nothing about the tag, and building on it would rewrite a
  multi-arch manifest as whatever happened to be legible.
  """
  def get_archs(kind, tag, fetch \\ &Bob.DockerHub.fetch_tag/2) do
    @archs
    |> Enum.reduce_while([], fn arch, acc ->
      case fetch.("hexpm/#{kind}-#{arch}", tag) do
        {:ok, {_tag, _archs, built_at}} -> {:cont, [{arch, built_at} | acc]}
        :not_found -> {:cont, acc}
        :unreadable -> {:halt, {:unreadable, arch}}
      end
    end)
    |> case do
      {:unreadable, arch} -> {:unreadable, arch}
      sources -> {:ok, Enum.reverse(sources)}
    end
  end
end
