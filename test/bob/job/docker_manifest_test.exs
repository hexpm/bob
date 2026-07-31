defmodule Bob.Job.DockerManifestTest do
  use ExUnit.Case, async: true

  alias Bob.Job.DockerManifest

  defp fetcher(results) do
    fn repo, _tag ->
      arch = repo |> String.split("-") |> List.last()
      Map.fetch!(results, arch)
    end
  end

  defp built(arch), do: {:ok, {"a-tag", [arch], DateTime.utc_now()}}

  describe "get_archs/3" do
    test "publishes from every arch Docker Hub has" do
      fetch = fetcher(%{"amd64" => built("amd64"), "arm64" => built("arm64")})

      assert DockerManifest.get_archs("elixir", "a-tag", fetch) == {:ok, ["amd64", "arm64"]}
    end

    test "publishes from what is there while the other arch is still building" do
      fetch = fetcher(%{"amd64" => built("amd64"), "arm64" => :not_found})

      assert DockerManifest.get_archs("elixir", "a-tag", fetch) == {:ok, ["amd64"]}
    end

    test "publishes nothing when neither arch is there" do
      fetch = fetcher(%{"amd64" => :not_found, "arm64" => :not_found})

      assert DockerManifest.get_archs("elixir", "a-tag", fetch) == {:ok, []}
    end

    test "refuses to publish when an arch did not read" do
      # Answering on this would rewrite a two-arch manifest as amd64 only.
      fetch = fetcher(%{"amd64" => built("amd64"), "arm64" => :unreadable})

      assert DockerManifest.get_archs("elixir", "a-tag", fetch) == {:unreadable, "arm64"}
    end

    test "refuses to publish when the first arch did not read" do
      fetch = fetcher(%{"amd64" => :unreadable, "arm64" => built("arm64")})

      assert DockerManifest.get_archs("elixir", "a-tag", fetch) == {:unreadable, "amd64"}
    end
  end
end
