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
    Bob.FakeGitHub.reset()
    :ok
  end

  describe "latest_erlang_refs/1" do
    test "keeps only the newest ref per major.minor line" do
      refs = ["OTP-26.2", "OTP-26.2.5", "OTP-26.2.5.21", "OTP-26.1.2", "OTP-27.0"]

      assert DockerChecker.latest_erlang_refs(refs) ==
               ["OTP-27.0", "OTP-26.2.5.21", "OTP-26.1.2"]
    end

    test "orders multi-component patch versions numerically" do
      refs = ["OTP-26.2.5.3", "OTP-26.2.5.21"]

      assert DockerChecker.latest_erlang_refs(refs) == ["OTP-26.2.5.21"]
    end

    test "drops prereleases once a stable release exists in the line" do
      refs = ["OTP-29.0-rc1", "OTP-29.0-rc3", "OTP-29.0.2"]

      assert DockerChecker.latest_erlang_refs(refs) == ["OTP-29.0.2"]
    end

    test "keeps the newest prerelease in a line without stable releases" do
      refs = ["OTP-30.0-rc1", "OTP-30.0-rc2", "OTP-29.0.2"]

      assert DockerChecker.latest_erlang_refs(refs) == ["OTP-30.0-rc2", "OTP-29.0.2"]
    end

    test "is independent of input order" do
      refs = ["OTP-26.2.5.21", "OTP-27.0", "OTP-26.2", "OTP-26.1.2", "OTP-26.2.5"]

      assert DockerChecker.latest_erlang_refs(refs) ==
               ["OTP-27.0", "OTP-26.2.5.21", "OTP-26.1.2"]
    end
  end

  describe "latest_elixir_builds/1" do
    test "keeps only the newest build per elixir minor and otp major" do
      builds = [
        {"v1.19.0", "27"},
        {"v1.19.5", "27"},
        {"v1.19.5", "28"},
        {"v1.18.4", "27"}
      ]

      assert DockerChecker.latest_elixir_builds(builds) ==
               [{"v1.19.5", "28"}, {"v1.19.5", "27"}, {"v1.18.4", "27"}]
    end

    test "drops prereleases once a stable release exists in the minor" do
      builds = [{"v1.19.0-rc.0", "27"}, {"v1.19.5", "27"}]

      assert DockerChecker.latest_elixir_builds(builds) == [{"v1.19.5", "27"}]
    end

    test "normalizes two-component versions" do
      builds = [{"v1.18", "27"}, {"v1.18.4", "27"}]

      assert DockerChecker.latest_elixir_builds(builds) == [{"v1.18.4", "27"}]
    end
  end

  describe "expected_erlang_tags/0" do
    test "crosses only the latest patch per minor with current base images" do
      Repo.insert!(%BaseImageTag{repo: "library/ubuntu", tag: "noble-20250101"})

      Bob.FakeGitHub.stub_refs("erlang/otp", [
        {"OTP-26.2.5", "sha1"},
        {"OTP-26.2.5.21", "sha2"},
        {"OTP-27.0", "sha3"}
      ])

      assert Enum.sort(DockerChecker.expected_erlang_tags()) ==
               Enum.sort([
                 {"26.2.5.21", "ubuntu", "noble-20250101", "amd64"},
                 {"26.2.5.21", "ubuntu", "noble-20250101", "arm64"},
                 {"27.0", "ubuntu", "noble-20250101", "amd64"},
                 {"27.0", "ubuntu", "noble-20250101", "arm64"}
               ])
    end

    test "applies the os rules after the latest-patch collapse" do
      Repo.insert!(%BaseImageTag{repo: "library/ubuntu", tag: "resolute-20260101"})

      Bob.FakeGitHub.stub_refs("erlang/otp", [
        {"OTP-25.3.2.21", "sha1"},
        {"OTP-26.2.5.21", "sha2"}
      ])

      assert Enum.sort(DockerChecker.expected_erlang_tags()) ==
               Enum.sort([
                 {"26.2.5.21", "ubuntu", "resolute-20260101", "amd64"},
                 {"26.2.5.21", "ubuntu", "resolute-20260101", "arm64"}
               ])
    end
  end

  describe "valid_erlang_build?/3" do
    test "requires openssl 3 support on ubuntu and debian" do
      refute DockerChecker.valid_erlang_build?("24.1", "ubuntu", "noble-20250101")
      assert DockerChecker.valid_erlang_build?("24.2", "ubuntu", "noble-20250101")
      refute DockerChecker.valid_erlang_build?("24.1", "debian", "bookworm-20250101")
      assert DockerChecker.valid_erlang_build?("24.2", "debian", "bookworm-20250101")
    end

    test "requires c23 compatibility on ubuntu resolute" do
      refute DockerChecker.valid_erlang_build?("25.3.2.21", "ubuntu", "resolute-20260101")
      refute DockerChecker.valid_erlang_build?("26.0-rc3", "ubuntu", "resolute-20260101")
      assert DockerChecker.valid_erlang_build?("26.0", "ubuntu", "resolute-20260101")
    end

    test "applies the alpine rules" do
      refute DockerChecker.valid_erlang_build?("20.3", "alpine", "3.22.1")
      refute DockerChecker.valid_erlang_build?("25.3", "alpine", "3.23.5")
      assert DockerChecker.valid_erlang_build?("26.1", "alpine", "3.23.5")
    end
  end

  describe "valid_elixir_build?/5" do
    test "accepts a compatible combination" do
      assert DockerChecker.valid_elixir_build?("1.18.0", "27", "27.0", "ubuntu", "noble-20250101")
    end

    test "rejects an otp major mismatch" do
      refute DockerChecker.valid_elixir_build?("1.18.0", "26", "27.0", "ubuntu", "noble-20250101")
    end

    test "rejects erlang versions elixir is never built for" do
      refute DockerChecker.valid_elixir_build?(
               "1.14.5",
               "26",
               "26.0-rc1",
               "ubuntu",
               "noble-20250101"
             )
    end

    test "rejects elixir versions below 1.10" do
      refute DockerChecker.valid_elixir_build?(
               "1.9.4",
               "22",
               "22.3",
               "debian",
               "bullseye-20250101"
             )
    end

    test "rejects prereleases below 1.12" do
      refute DockerChecker.valid_elixir_build?(
               "1.11.0-rc.0",
               "23",
               "23.3",
               "debian",
               "bullseye-20250101"
             )
    end

    test "rejects combinations the erlang rules reject" do
      refute DockerChecker.valid_elixir_build?("1.18.0", "24", "24.1", "ubuntu", "noble-20250101")
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

  describe "expected_elixir_tags/0" do
    test "crosses current-os-version erlang tags with compatible elixir builds" do
      Repo.insert!(%BaseImageTag{repo: "library/ubuntu", tag: "noble-20250101"})
      Bob.FakeGitHub.stub_refs("erlang/otp", [{"OTP-27.0", "sha"}])
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

    test "expands only over the latest patch per erlang minor" do
      Repo.insert!(%BaseImageTag{repo: "library/ubuntu", tag: "noble-20250101"})
      Bob.FakeGitHub.stub_refs("erlang/otp", [{"OTP-27.0", "sha1"}, {"OTP-27.0.1", "sha2"}])
      Artifacts.add_docker_tag("hexpm/erlang-amd64", "27.0.1-ubuntu-noble-20250101", ["amd64"])
      # An erlang tag that is not the latest patch, e.g. built on user request,
      # contributes nothing.
      Artifacts.add_docker_tag("hexpm/erlang-amd64", "27.0-ubuntu-noble-20250101", ["amd64"])

      Bob.FakeHttpClient.stub(:get, @builds_txt_url, 200, "v1.18.0-otp-27 abc123\n")

      assert Enum.to_list(DockerChecker.expected_elixir_tags()) ==
               [{"1.18.0", "27.0.1", "ubuntu", "noble-20250101", "amd64"}]
    end

    test "expands only over the latest elixir build per minor and otp major" do
      Repo.insert!(%BaseImageTag{repo: "library/ubuntu", tag: "noble-20250101"})
      Bob.FakeGitHub.stub_refs("erlang/otp", [{"OTP-27.0", "sha"}])
      Artifacts.add_docker_tag("hexpm/erlang-amd64", "27.0-ubuntu-noble-20250101", ["amd64"])

      Bob.FakeHttpClient.stub(
        :get,
        @builds_txt_url,
        200,
        "v1.18.0-otp-27 abc123\nv1.18.4-otp-27 def456\n"
      )

      assert Enum.to_list(DockerChecker.expected_elixir_tags()) ==
               [{"1.18.4", "27.0", "ubuntu", "noble-20250101", "amd64"}]
    end
  end

  describe "elixir/0" do
    setup do
      Repo.insert!(%BaseImageTag{repo: "library/ubuntu", tag: "noble-20250101"})
      Bob.FakeGitHub.stub_refs("erlang/otp", [{"OTP-27.0", "sha"}])
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
