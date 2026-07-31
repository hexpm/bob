defmodule Bob.Job.DockerManifestTest do
  use ExUnit.Case, async: true

  alias Bob.Job.DockerManifest

  @epoch ~U[2026-01-01 00:00:00Z]

  defp at(seconds), do: DateTime.add(@epoch, seconds, :second)

  defp fetcher(results) do
    fn repo, _tag ->
      arch = repo |> String.split("-") |> List.last()
      Map.fetch!(results, arch)
    end
  end

  defp built(arch, seconds \\ 0), do: {:ok, {"a-tag", [arch], at(seconds)}}

  defp manifest(archs, seconds),
    do: fn "hexpm/elixir", _tag -> {:ok, {"a-tag", archs, at(seconds)}} end

  describe "get_archs/3" do
    test "takes every arch Docker Hub has, with when it was pushed" do
      fetch = fetcher(%{"amd64" => built("amd64", 10), "arm64" => built("arm64", 20)})

      assert DockerManifest.get_archs("elixir", "a-tag", fetch) ==
               {:ok, [{"amd64", at(10)}, {"arm64", at(20)}]}
    end

    test "takes what is there while the other arch is still building" do
      fetch = fetcher(%{"amd64" => built("amd64"), "arm64" => :not_found})

      assert DockerManifest.get_archs("elixir", "a-tag", fetch) == {:ok, [{"amd64", at(0)}]}
    end

    test "takes nothing when neither arch is there" do
      fetch = fetcher(%{"amd64" => :not_found, "arm64" => :not_found})

      assert DockerManifest.get_archs("elixir", "a-tag", fetch) == {:ok, []}
    end

    test "refuses when an arch did not read" do
      # Answering on this would rewrite a two-arch manifest as amd64 only.
      fetch = fetcher(%{"amd64" => built("amd64"), "arm64" => :unreadable})

      assert DockerManifest.get_archs("elixir", "a-tag", fetch) == {:unreadable, "arm64"}
    end

    test "refuses when the first arch did not read" do
      fetch = fetcher(%{"amd64" => :unreadable, "arm64" => built("arm64")})

      assert DockerManifest.get_archs("elixir", "a-tag", fetch) == {:unreadable, "amd64"}
    end
  end

  describe "publish?/4" do
    test "builds when there is no manifest yet" do
      fetch = fn "hexpm/elixir", _tag -> :not_found end

      assert DockerManifest.publish?("elixir", "a-tag", [{"amd64", at(0)}], fetch)
    end

    test "builds when the set grows" do
      sources = [{"amd64", at(0)}, {"arm64", at(10)}]

      assert DockerManifest.publish?("elixir", "a-tag", sources, manifest(["amd64"], 5))
    end

    test "builds when a source was pushed after the manifest was built" do
      # The same tag can be re-pushed under a new digest, and the manifest has
      # to follow it.
      sources = [{"amd64", at(100)}, {"arm64", at(10)}]

      assert DockerManifest.publish?("elixir", "a-tag", sources, manifest(["amd64", "arm64"], 50))
    end

    test "leaves a manifest newer than all of its sources alone" do
      sources = [{"amd64", at(10)}, {"arm64", at(20)}]

      refute DockerManifest.publish?("elixir", "a-tag", sources, manifest(["amd64", "arm64"], 50))
    end

    test "leaves a manifest alone when an arch it spans is gone" do
      # The per-arch tag the other half was built from is cleaned up after 30
      # days, so this would republish a two-arch tag as one.
      sources = [{"amd64", at(100)}]

      refute DockerManifest.publish?("elixir", "a-tag", sources, manifest(["amd64", "arm64"], 50))
    end

    test "leaves a manifest alone when the sets only overlap" do
      sources = [{"arm64", at(100)}]

      refute DockerManifest.publish?("elixir", "a-tag", sources, manifest(["amd64"], 50))
    end

    test "leaves a manifest alone when it did not read" do
      fetch = fn "hexpm/elixir", _tag -> :unreadable end
      sources = [{"amd64", at(0)}, {"arm64", at(0)}]

      refute DockerManifest.publish?("elixir", "a-tag", sources, fetch)
    end
  end
end
