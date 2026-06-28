defmodule Bob.Job.DockerCheckerTest do
  use Bob.DataCase

  import ExUnit.CaptureLog

  alias Bob.Job.DockerChecker
  alias Bob.Artifacts
  alias Bob.Artifacts.BaseImageTag
  alias Bob.Queue.Job

  setup do
    Bob.FakeGitHub.reset()
    Bob.Cache.clear()
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

  describe "elixir_builds/0" do
    test "uses OTP-specific zip assets from GitHub releases" do
      Bob.FakeGitHub.stub_releases("elixir-lang/elixir", [
        release("v1.18.0", ["27", "26", "exe-25"]),
        release("v1.18.4", ["27", "26"]),
        release("v1.20-latest", ["29"]),
        release("v1.9.4", ["21"]),
        release("v1.11.0-rc.0", ["23"])
      ])

      assert DockerChecker.elixir_builds() ==
               [
                 {"v1.18.4", "27"},
                 {"v1.18.4", "26"},
                 {"v1.18.0", "27"},
                 {"v1.18.0", "26"}
               ]
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
      for tag <- ["3.24.0", "3.23.4", "3.23.5", "3.22.1"] do
        Repo.insert!(%BaseImageTag{repo: "library/alpine", tag: tag})
      end

      assert DockerChecker.builds()["alpine"] == ["3.24.0", "3.23.5", "3.22.1"]
    end

    test "yields no versions when base_image_tags is empty" do
      assert DockerChecker.builds()["alpine"] == []
    end
  end

  describe "expected_elixir_tags/0" do
    test "crosses current-os-version erlang tags with compatible elixir builds" do
      Repo.insert!(%BaseImageTag{repo: "library/ubuntu", tag: "noble-20250101"})
      Bob.FakeGitHub.stub_refs("erlang/otp", [{"OTP-27.0", "sha"}])
      Bob.FakeGitHub.stub_releases("elixir-lang/elixir", [release("v1.18.0", ["27", "26"])])
      Artifacts.add_docker_tag("hexpm/erlang-amd64", "27.0-ubuntu-noble-20250101", ["amd64"])
      # An erlang tag on a base image that is no longer current contributes nothing.
      Artifacts.add_docker_tag("hexpm/erlang-arm64", "27.0-ubuntu-noble-20240101", ["arm64"])

      assert Enum.to_list(DockerChecker.expected_elixir_tags()) ==
               [{"1.18.0", "27.0", "ubuntu", "noble-20250101", "amd64"}]
    end

    test "expands only over the latest patch per erlang minor" do
      Repo.insert!(%BaseImageTag{repo: "library/ubuntu", tag: "noble-20250101"})
      Bob.FakeGitHub.stub_refs("erlang/otp", [{"OTP-27.0", "sha1"}, {"OTP-27.0.1", "sha2"}])
      Bob.FakeGitHub.stub_releases("elixir-lang/elixir", [release("v1.18.0", ["27"])])
      Artifacts.add_docker_tag("hexpm/erlang-amd64", "27.0.1-ubuntu-noble-20250101", ["amd64"])
      # An erlang tag that is not the latest patch, e.g. built on user request,
      # contributes nothing.
      Artifacts.add_docker_tag("hexpm/erlang-amd64", "27.0-ubuntu-noble-20250101", ["amd64"])

      assert Enum.to_list(DockerChecker.expected_elixir_tags()) ==
               [{"1.18.0", "27.0.1", "ubuntu", "noble-20250101", "amd64"}]
    end

    test "expands only over the latest elixir build per minor and otp major" do
      Repo.insert!(%BaseImageTag{repo: "library/ubuntu", tag: "noble-20250101"})
      Bob.FakeGitHub.stub_refs("erlang/otp", [{"OTP-27.0", "sha"}])

      Bob.FakeGitHub.stub_releases("elixir-lang/elixir", [
        release("v1.18.0", ["27"]),
        release("v1.18.4", ["27"])
      ])

      Artifacts.add_docker_tag("hexpm/erlang-amd64", "27.0-ubuntu-noble-20250101", ["amd64"])

      assert Enum.to_list(DockerChecker.expected_elixir_tags()) ==
               [{"1.18.4", "27.0", "ubuntu", "noble-20250101", "amd64"}]
    end
  end

  describe "elixir/0" do
    setup do
      Repo.insert!(%BaseImageTag{repo: "library/ubuntu", tag: "noble-20250101"})
      Bob.FakeGitHub.stub_refs("erlang/otp", [{"OTP-27.0", "sha"}])
      Bob.FakeGitHub.stub_releases("elixir-lang/elixir", [release("v1.18.0", ["27"])])
      Artifacts.add_docker_tag("hexpm/erlang-amd64", "27.0-ubuntu-noble-20250101", ["amd64"])
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

  describe "build freshness" do
    test "erlang/0 skips combos whose components were all released long ago" do
      insert_base_image("library/ubuntu", "noble-20240101", 60)
      Bob.FakeGitHub.stub_refs("erlang/otp", [{"OTP-27.0.1", "sha"}])
      Bob.FakeGitHub.stub_releases("erlang/otp", [otp_release("OTP-27.0.1", days_ago_iso(60))])

      DockerChecker.erlang()

      assert Repo.all(Job) == []
    end

    test "erlang/0 builds when the OTP version was released recently" do
      insert_base_image("library/ubuntu", "noble-20240101", 60)
      Bob.FakeGitHub.stub_refs("erlang/otp", [{"OTP-27.0.1", "sha"}])
      Bob.FakeGitHub.stub_releases("erlang/otp", [otp_release("OTP-27.0.1", days_ago_iso(2))])

      DockerChecker.erlang()

      assert Enum.count(Repo.all(Job)) == 2
    end

    test "erlang/0 builds when the base image is recent even for an old OTP" do
      insert_base_image("library/ubuntu", "noble-20250601", 2)
      Bob.FakeGitHub.stub_refs("erlang/otp", [{"OTP-27.0.1", "sha"}])
      Bob.FakeGitHub.stub_releases("erlang/otp", [otp_release("OTP-27.0.1", days_ago_iso(400))])

      DockerChecker.erlang()

      assert Enum.count(Repo.all(Job)) == 2
    end

    test "elixir/0 builds when the Elixir version was released recently" do
      insert_base_image("library/ubuntu", "noble-20240101", 60)
      Bob.FakeGitHub.stub_refs("erlang/otp", [{"OTP-27.0", "sha"}])
      Bob.FakeGitHub.stub_releases("erlang/otp", [otp_release("OTP-27.0", days_ago_iso(400))])
      Artifacts.add_docker_tag("hexpm/erlang-amd64", "27.0-ubuntu-noble-20240101", ["amd64"])

      Bob.FakeGitHub.stub_releases("elixir-lang/elixir", [
        release("v1.18.0", ["27"], days_ago_iso(2))
      ])

      DockerChecker.elixir()

      assert [%Job{module_key: {Bob.Job.BuildDockerElixir, "amd64"}}] = Repo.all(Job)
    end

    test "elixir/0 skips when every component is old" do
      insert_base_image("library/ubuntu", "noble-20240101", 60)
      Bob.FakeGitHub.stub_refs("erlang/otp", [{"OTP-27.0", "sha"}])
      Bob.FakeGitHub.stub_releases("erlang/otp", [otp_release("OTP-27.0", days_ago_iso(400))])
      Artifacts.add_docker_tag("hexpm/erlang-amd64", "27.0-ubuntu-noble-20240101", ["amd64"])

      Bob.FakeGitHub.stub_releases("elixir-lang/elixir", [
        release("v1.18.0", ["27"], days_ago_iso(400))
      ])

      DockerChecker.elixir()

      assert Repo.all(Job) == []
    end
  end

  describe "requests/0" do
    setup do
      Repo.insert!(%BaseImageTag{repo: "library/ubuntu", tag: "noble-20250101"})
      :ok
    end

    test "enqueues missing builds and keeps the request pending" do
      request = insert_request(kind: "erlang", erlang: "27.0")

      DockerChecker.requests()

      assert Enum.count(Repo.all(Job)) == 2
      assert Repo.reload!(request).state == "pending"
    end

    test "enqueues the manifest once the erlang archs are built" do
      request = insert_request(kind: "erlang", erlang: "27.0")
      Artifacts.add_docker_tag("hexpm/erlang-amd64", "27.0-ubuntu-noble-20250101", ["amd64"])
      Artifacts.add_docker_tag("hexpm/erlang-arm64", "27.0-ubuntu-noble-20250101", ["arm64"])

      DockerChecker.requests()

      assert [%Job{module_key: Bob.Job.DockerManifest, args: args}] = Repo.all(Job)
      assert args == ["erlang", {"27.0", "ubuntu", "noble-20250101"}]
      assert Repo.reload!(request).state == "pending"
    end

    test "completes an erlang request once the manifest spans both archs" do
      request = insert_request(kind: "erlang", erlang: "27.0")
      Artifacts.add_docker_tag("hexpm/erlang-amd64", "27.0-ubuntu-noble-20250101", ["amd64"])
      Artifacts.add_docker_tag("hexpm/erlang-arm64", "27.0-ubuntu-noble-20250101", ["arm64"])
      Artifacts.add_docker_tag("hexpm/erlang", "27.0-ubuntu-noble-20250101", ["amd64", "arm64"])

      DockerChecker.requests()

      assert Repo.all(Job) == []
      assert Repo.reload!(request).state == "completed"
    end

    test "keeps an erlang request pending while the manifest covers one arch" do
      request = insert_request(kind: "erlang", erlang: "27.0")
      Artifacts.add_docker_tag("hexpm/erlang-amd64", "27.0-ubuntu-noble-20250101", ["amd64"])
      Artifacts.add_docker_tag("hexpm/erlang-arm64", "27.0-ubuntu-noble-20250101", ["arm64"])
      Artifacts.add_docker_tag("hexpm/erlang", "27.0-ubuntu-noble-20250101", ["amd64"])

      DockerChecker.requests()

      assert [%Job{module_key: Bob.Job.DockerManifest}] = Repo.all(Job)
      assert Repo.reload!(request).state == "pending"
    end

    test "stages an elixir request through the erlang base build" do
      request = insert_request(kind: "elixir", elixir: "1.18.0", erlang: "27.0")
      Artifacts.add_docker_tag("hexpm/erlang-amd64", "27.0-ubuntu-noble-20250101", ["amd64"])

      DockerChecker.requests()

      jobs = Repo.all(Job) |> Enum.map(&{&1.module_key, &1.args}) |> Enum.sort()

      assert jobs ==
               Enum.sort([
                 {{Bob.Job.BuildDockerElixir, "amd64"},
                  ["1.18.0", "27.0", "ubuntu", "noble-20250101"]},
                 {{Bob.Job.BuildDockerErlang, "arm64"}, ["27.0", "ubuntu", "noble-20250101"]}
               ])

      assert Repo.reload!(request).state == "pending"
    end

    test "completes an elixir request once the manifest spans both archs" do
      request = insert_request(kind: "elixir", elixir: "1.18.0", erlang: "27.0")
      tag = "1.18.0-erlang-27.0-ubuntu-noble-20250101"

      Artifacts.add_docker_tag("hexpm/elixir-amd64", tag, ["amd64"])
      Artifacts.add_docker_tag("hexpm/elixir-arm64", tag, ["arm64"])
      Artifacts.add_docker_tag("hexpm/elixir", tag, ["amd64", "arm64"])

      DockerChecker.requests()

      assert Repo.all(Job) == []
      assert Repo.reload!(request).state == "completed"
    end

    test "enqueues the manifest once the elixir archs are built" do
      request = insert_request(kind: "elixir", elixir: "1.18.0", erlang: "27.0")
      tag = "1.18.0-erlang-27.0-ubuntu-noble-20250101"

      Artifacts.add_docker_tag("hexpm/elixir-amd64", tag, ["amd64"])
      Artifacts.add_docker_tag("hexpm/elixir-arm64", tag, ["arm64"])

      DockerChecker.requests()

      assert [%Job{module_key: Bob.Job.DockerManifest, args: args}] = Repo.all(Job)
      assert args == ["elixir", {"1.18.0", "27.0", "ubuntu", "noble-20250101"}]
      assert Repo.reload!(request).state == "pending"
    end

    test "expires requests whose os_version is no longer current" do
      request = insert_request(kind: "erlang", erlang: "27.0", os_version: "noble-20240101")

      DockerChecker.requests()

      assert Repo.all(Job) == []
      assert Repo.reload!(request).state == "expired"
    end

    test "expires requests that never completed within the ttl" do
      request = insert_request(kind: "erlang", erlang: "27.0")

      request
      |> Ecto.Changeset.change(inserted_at: DateTime.add(DateTime.utc_now(), -15, :day))
      |> Repo.update!()

      DockerChecker.requests()

      assert Repo.all(Job) == []
      assert Repo.reload!(request).state == "expired"
    end

    test "does not duplicate jobs already queued" do
      insert_request(kind: "erlang", erlang: "27.0")

      DockerChecker.requests()
      DockerChecker.requests()

      assert Enum.count(Repo.all(Job)) == 2
    end

    defp insert_request(attrs) do
      attrs =
        Enum.into(attrs, %{
          username: "eric",
          os: "ubuntu",
          os_version: "noble-20250101",
          builds_count: 2
        })

      {:ok, request} = Bob.BuildRequests.create(attrs)
      request
    end
  end

  defp release(tag_name, otp_majors, published_at \\ now_iso()) do
    assets =
      Enum.map(otp_majors, fn
        "exe-" <> otp -> %{"name" => "elixir-otp-#{otp}.exe"}
        otp -> %{"name" => "elixir-otp-#{otp}.zip"}
      end)

    %{"tag_name" => tag_name, "assets" => assets, "published_at" => published_at}
  end

  defp otp_release(tag_name, published_at) do
    %{"tag_name" => tag_name, "published_at" => published_at}
  end

  defp now_iso(), do: DateTime.utc_now() |> DateTime.to_iso8601()

  defp days_ago_iso(days) do
    DateTime.utc_now() |> DateTime.add(-days, :day) |> DateTime.to_iso8601()
  end

  defp insert_base_image(repo, tag, days_old) do
    %BaseImageTag{repo: repo, tag: tag}
    |> Repo.insert!()
    |> Ecto.Changeset.change(inserted_at: DateTime.add(DateTime.utc_now(), -days_old, :day))
    |> Repo.update!()
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
