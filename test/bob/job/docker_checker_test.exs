defmodule Bob.Job.DockerCheckerTest do
  use Bob.DataCase

  import ExUnit.CaptureLog

  alias Bob.Job.DockerChecker
  alias Bob.Artifacts
  alias Bob.Artifacts.BaseImageTag
  alias Bob.Queue.Job

  @builds_txt_url "https://s3.amazonaws.com/s3.hex.pm/builds/elixir/builds.txt"

  setup do
    Bob.FakeHttpClient.reset()
    :ok
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

  describe "expected_elixir_tags/0" do
    test "crosses current-os-version erlang tags with compatible elixir builds" do
      Repo.insert!(%BaseImageTag{repo: "library/ubuntu", tag: "noble-20250101"})
      Artifacts.add_docker_tag("hexpm/erlang-amd64", "27.0-ubuntu-noble-20250101", ["amd64"])
      # An erlang tag on a base image that is no longer current contributes nothing.
      Artifacts.add_docker_tag("hexpm/erlang-arm64", "27.0-ubuntu-noble-20240101", ["arm64"])

      Bob.FakeHttpClient.stub(
        :get,
        @builds_txt_url,
        200,
        "v1.18.0-otp-27 abc123\nv1.18.0-otp-26 def456\n"
      )

      assert Enum.to_list(DockerChecker.expected_elixir_tags()) ==
               [{"1.18.0", "27.0", "ubuntu", "noble-20250101", "amd64"}]
    end
  end

  describe "elixir/0" do
    setup do
      Repo.insert!(%BaseImageTag{repo: "library/ubuntu", tag: "noble-20250101"})
      Artifacts.add_docker_tag("hexpm/erlang-amd64", "27.0-ubuntu-noble-20250101", ["amd64"])
      Bob.FakeHttpClient.stub(:get, @builds_txt_url, 200, "v1.18.0-otp-27 abc123\n")
      :ok
    end

    test "enqueues builds for expected elixir tags missing from the mirror" do
      DockerChecker.elixir()

      assert [%Job{module_key: {Bob.Job.BuildDockerElixir, "amd64"}, args: args}] = Repo.all(Job)
      assert args == ["1.18.0", "27.0", "ubuntu", "noble-20250101"]
    end

    test "does not enqueue elixir tags that are already built" do
      Artifacts.add_docker_tag(
        "hexpm/elixir-amd64",
        "1.18.0-erlang-27.0-ubuntu-noble-20250101",
        ["amd64"]
      )

      DockerChecker.elixir()

      assert Repo.all(Job) == []
    end
  end

  describe "manifest/0" do
    test "enqueues manifest jobs for per-arch tags missing from the manifest repo" do
      Artifacts.add_docker_tag("hexpm/erlang-amd64", "27.0-ubuntu-noble-20250101", ["amd64"])
      Artifacts.add_docker_tag("hexpm/erlang-arm64", "27.0-ubuntu-noble-20250101", ["arm64"])

      Artifacts.add_docker_tag(
        "hexpm/elixir-amd64",
        "1.18.0-erlang-27.0-ubuntu-noble-20250101",
        ["amd64"]
      )

      DockerChecker.manifest()

      jobs = Repo.all(Job) |> Enum.map(&{&1.module_key, &1.args}) |> Enum.sort()

      assert jobs ==
               Enum.sort([
                 {Bob.Job.DockerManifest, ["erlang", {"27.0", "ubuntu", "noble-20250101"}]},
                 {Bob.Job.DockerManifest,
                  ["elixir", {"1.18.0", "27.0", "ubuntu", "noble-20250101"}]}
               ])
    end

    test "does not enqueue when the manifest already covers the built archs" do
      Artifacts.add_docker_tag("hexpm/erlang-amd64", "27.0-ubuntu-noble-20250101", ["amd64"])
      Artifacts.add_docker_tag("hexpm/erlang-arm64", "27.0-ubuntu-noble-20250101", ["arm64"])
      Artifacts.add_docker_tag("hexpm/erlang", "27.0-ubuntu-noble-20250101", ["amd64", "arm64"])

      DockerChecker.manifest()

      assert Repo.all(Job) == []
    end

    test "enqueues when the manifest lacks one of the built archs" do
      Artifacts.add_docker_tag("hexpm/erlang-amd64", "27.0-ubuntu-noble-20250101", ["amd64"])
      Artifacts.add_docker_tag("hexpm/erlang-arm64", "27.0-ubuntu-noble-20250101", ["arm64"])
      Artifacts.add_docker_tag("hexpm/erlang", "27.0-ubuntu-noble-20250101", ["amd64"])

      DockerChecker.manifest()

      assert [%Job{module_key: Bob.Job.DockerManifest, args: args}] = Repo.all(Job)
      assert args == ["erlang", {"27.0", "ubuntu", "noble-20250101"}]
    end

    test "skips per-arch tags that cannot be parsed instead of crashing" do
      Artifacts.add_docker_tag("hexpm/erlang-amd64", "latest", ["amd64"])
      Artifacts.add_docker_tag("hexpm/erlang-amd64", "27.0-ubuntu-noble-20250101", ["amd64"])

      log = capture_log(fn -> DockerChecker.manifest() end)

      assert log =~ "latest"
      assert [%Job{module_key: Bob.Job.DockerManifest, args: args}] = Repo.all(Job)
      assert args == ["erlang", {"27.0", "ubuntu", "noble-20250101"}]
    end
  end
end
