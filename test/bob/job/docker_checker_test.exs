defmodule Bob.Job.DockerCheckerTest do
  use Bob.DataCase

  alias Bob.Job.DockerChecker
  alias Bob.Artifacts
  alias Bob.Artifacts.BaseImageTag
  alias Bob.Queue.Job

  describe "erlang_tags/1" do
    test "reads and parses per-arch erlang tags from docker_tags" do
      Artifacts.add_docker_tag("hexpm/erlang-amd64", "27.0-ubuntu-noble-20250101", ["amd64"])

      assert DockerChecker.erlang_tags("amd64") ==
               [{"27.0", "ubuntu", "noble-20250101", "amd64"}]
    end
  end

  describe "elixir_tags/1" do
    test "reads and parses per-arch elixir tags from docker_tags" do
      Artifacts.add_docker_tag(
        "hexpm/elixir-amd64",
        "1.18.0-erlang-27.0-ubuntu-noble-20250101",
        ["amd64"]
      )

      assert DockerChecker.elixir_tags("amd64") ==
               [{"1.18.0", "27.0", "ubuntu", "noble-20250101", "amd64"}]
    end
  end

  describe "erlang_manifest_tags/0" do
    test "reads manifest tags with their archs from docker_tags" do
      Artifacts.add_docker_tag("hexpm/erlang", "27.0-ubuntu-noble-20250101", ["amd64", "arm64"])

      assert DockerChecker.erlang_manifest_tags() ==
               %{{"27.0", "ubuntu", "noble-20250101"} => ["amd64", "arm64"]}
    end
  end

  describe "elixir_manifest_tags/0" do
    test "reads manifest tags with their archs from docker_tags" do
      Artifacts.add_docker_tag(
        "hexpm/elixir",
        "1.18.0-erlang-27.0-ubuntu-noble-20250101",
        ["amd64", "arm64"]
      )

      assert DockerChecker.elixir_manifest_tags() ==
               %{{"1.18.0", "27.0", "ubuntu", "noble-20250101"} => ["amd64", "arm64"]}
    end
  end

  describe "builds/0" do
    test "finds the latest base-image tag matching each regex" do
      for tag <- ["3.23.4", "3.23.5", "3.22.1"] do
        Repo.insert!(%BaseImageTag{repo: "library/alpine", tag: tag})
      end

      assert DockerChecker.builds()["alpine"] == ["3.23.5", "3.22.1"]
    end

    test "yields no versions when base_image_tags is empty" do
      assert DockerChecker.builds()["alpine"] == []
    end
  end

  describe "diff_manifests/3" do
    test "enqueues a manifest job when expected archs are missing" do
      expected = %{{"27.0", "ubuntu", "noble-20250101"} => ["amd64", "arm64"]}

      DockerChecker.diff_manifests("erlang", expected, %{})

      assert [%Job{module_key: Bob.Job.DockerManifest, args: args}] = Repo.all(Job)
      assert args == ["erlang", {"27.0", "ubuntu", "noble-20250101"}]
    end

    test "does not enqueue when the manifest already has all archs" do
      key = {"27.0", "ubuntu", "noble-20250101"}
      expected = %{key => ["amd64", "arm64"]}
      current = %{key => ["amd64", "arm64"]}

      DockerChecker.diff_manifests("erlang", expected, current)

      assert Repo.all(Job) == []
    end

    test "enqueues when only some archs are present" do
      key = {"27.0", "ubuntu", "noble-20250101"}
      expected = %{key => ["amd64", "arm64"]}
      current = %{key => ["amd64"]}

      DockerChecker.diff_manifests("erlang", expected, current)

      assert [%Job{module_key: Bob.Job.DockerManifest}] = Repo.all(Job)
    end
  end

  describe "diff/2" do
    test "returns expected entries that are not in current" do
      expected = [{"a", 1}, {"b", 2}, {"c", 3}]
      current = [{"b", 2}]

      assert Enum.sort(DockerChecker.diff(expected, current)) == [{"a", 1}, {"c", 3}]
    end
  end
end
