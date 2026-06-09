defmodule Bob.ReconcileTest do
  use Bob.DataCase

  alias Bob.{Artifacts, Reconcile}

  @docker_built_at ~U[2025-01-02 03:04:05.000000Z]
  @newer_docker_built_at ~U[2025-02-03 04:05:06.000000Z]

  # Streamer stub: invokes on_page once with the canned {tag, archs, built_at} list for the
  # repo (mimicking a single Docker Hub page), or nothing for an empty repo.
  defp streamer(map) do
    fn repo, on_page ->
      case Map.get(map, repo, []) do
        [] -> :ok
        tags -> on_page.(tags)
      end

      :ok
    end
  end

  describe "reconcile/1" do
    test "stores per-arch erlang/elixir tags with the arch forced from the repo name" do
      stream =
        streamer(%{
          "hexpm/erlang-amd64" => [
            docker_tag("27.0-ubuntu-noble-20250101", ["amd64", "arm64"], @docker_built_at)
          ],
          "hexpm/elixir-arm64" => [
            docker_tag(
              "1.18.0-erlang-27.0-ubuntu-noble-20250101",
              ["amd64"],
              @newer_docker_built_at
            )
          ]
        })

      Reconcile.reconcile(stream)

      assert Artifacts.docker_tags("hexpm/erlang-amd64") ==
               [{"27.0-ubuntu-noble-20250101", ["amd64"]}]

      assert Artifacts.docker_tags("hexpm/elixir-arm64") ==
               [{"1.18.0-erlang-27.0-ubuntu-noble-20250101", ["arm64"]}]

      assert %Bob.Artifacts.DockerTag{built_at: @docker_built_at} =
               Repo.get_by!(Bob.Artifacts.DockerTag,
                 repo: "hexpm/erlang-amd64",
                 tag: "27.0-ubuntu-noble-20250101"
               )

      assert %Bob.Artifacts.DockerTag{built_at: @newer_docker_built_at} =
               Repo.get_by!(Bob.Artifacts.DockerTag,
                 repo: "hexpm/elixir-arm64",
                 tag: "1.18.0-erlang-27.0-ubuntu-noble-20250101"
               )
    end

    test "stores manifest tags with the upstream archs intersected with known archs, sorted" do
      stream =
        streamer(%{
          "hexpm/erlang" => [
            docker_tag("27.0-ubuntu-noble-20250101", ["arm64", "amd64", "ppc64le"])
          ]
        })

      Reconcile.reconcile(stream)

      assert Artifacts.docker_tags("hexpm/erlang") ==
               [{"27.0-ubuntu-noble-20250101", ["amd64", "arm64"]}]
    end

    test "stores only fully-multi-arch base image tags" do
      stream =
        streamer(%{
          "library/alpine" => [
            docker_tag("3.23.5", ["amd64", "arm64", "386"]),
            docker_tag("3.22.1", ["amd64"])
          ]
        })

      Reconcile.reconcile(stream)

      assert Artifacts.base_image_tags("library/alpine") == ["3.23.5"]
    end

    test "keeps existing base image tags when no upstream tag is fully multi-arch" do
      Artifacts.replace_base_image_tags("library/alpine", ["3.23.5"])

      stream = streamer(%{"library/alpine" => [docker_tag("3.24.0", ["amd64"])]})

      Reconcile.reconcile(stream)

      assert Artifacts.base_image_tags("library/alpine") == ["3.23.5"]
    end

    test "prunes docker tags that vanished upstream" do
      Artifacts.add_docker_tag("hexpm/erlang-amd64", "stale-tag", ["amd64"])

      stream = streamer(%{"hexpm/erlang-amd64" => [docker_tag("fresh-tag", ["amd64"])]})

      Reconcile.reconcile(stream)

      assert Artifacts.docker_tags("hexpm/erlang-amd64") == [{"fresh-tag", ["amd64"]}]
    end

    test "skips a repo whose fetch returns empty, leaving existing rows untouched" do
      Artifacts.add_docker_tag("hexpm/erlang-amd64", "keep-me", ["amd64"])

      Reconcile.reconcile(streamer(%{}))

      assert Artifacts.docker_tags("hexpm/erlang-amd64") == [{"keep-me", ["amd64"]}]
    end

    test "skips a repo whose fetch fails without wiping its rows or aborting siblings" do
      Artifacts.add_docker_tag("hexpm/erlang-amd64", "keep-me", ["amd64"])

      stream = fn
        "hexpm/erlang-amd64", _on_page -> :error
        "hexpm/elixir-arm64", on_page -> on_page.([docker_tag("fresh-tag", ["arm64"])])
        _repo, _on_page -> :ok
      end

      Reconcile.reconcile(stream)

      assert Artifacts.docker_tags("hexpm/erlang-amd64") == [{"keep-me", ["amd64"]}]
      assert Artifacts.docker_tags("hexpm/elixir-arm64") == [{"fresh-tag", ["arm64"]}]
    end

    test "skips a repo whose fetch crashes without wiping its rows or aborting siblings" do
      Artifacts.add_docker_tag("hexpm/erlang-amd64", "keep-me", ["amd64"])

      stream = fn
        "hexpm/erlang-amd64", _on_page -> raise "DockerHub paging blew up"
        "hexpm/elixir-arm64", on_page -> on_page.([docker_tag("fresh-tag", ["arm64"])])
        _repo, _on_page -> :ok
      end

      Reconcile.reconcile(stream)

      assert Artifacts.docker_tags("hexpm/erlang-amd64") == [{"keep-me", ["amd64"]}]
      assert Artifacts.docker_tags("hexpm/elixir-arm64") == [{"fresh-tag", ["arm64"]}]
    end

    test "leaves no staging rows behind after a run" do
      stream =
        streamer(%{
          "hexpm/erlang-amd64" => [docker_tag("27.0", ["amd64"])],
          "library/alpine" => [docker_tag("3.23.5", ["amd64", "arm64"])]
        })

      Reconcile.reconcile(stream)

      assert Repo.aggregate(Bob.Artifacts.DockerTagStaging, :count) == 0
    end
  end

  describe "reconcile_per_arch_repos/1" do
    test "reconciles the per-arch repos only" do
      Artifacts.add_docker_tag("hexpm/erlang", "untouched", ["amd64"])

      stream = streamer(%{"hexpm/erlang-amd64" => [docker_tag("27.0", ["amd64", "arm64"])]})

      Reconcile.reconcile_per_arch_repos(stream)

      assert Artifacts.docker_tags("hexpm/erlang-amd64") == [{"27.0", ["amd64"]}]
      assert Artifacts.docker_tags("hexpm/erlang") == [{"untouched", ["amd64"]}]
    end
  end

  describe "reconcile_manifest_repos/1" do
    test "reconciles the manifest repos only" do
      Artifacts.add_docker_tag("hexpm/erlang-amd64", "untouched", ["amd64"])

      stream = streamer(%{"hexpm/erlang" => [docker_tag("27.0", ["arm64", "amd64", "ppc64le"])]})

      Reconcile.reconcile_manifest_repos(stream)

      assert Artifacts.docker_tags("hexpm/erlang") == [{"27.0", ["amd64", "arm64"]}]
      assert Artifacts.docker_tags("hexpm/erlang-amd64") == [{"untouched", ["amd64"]}]
    end
  end

  describe "reconcile_base_images/1" do
    test "reconciles the base image repos only" do
      Artifacts.add_docker_tag("hexpm/erlang-amd64", "untouched", ["amd64"])

      stream = streamer(%{"library/alpine" => [docker_tag("3.23.5", ["amd64", "arm64"])]})

      Reconcile.reconcile_base_images(stream)

      assert Artifacts.base_image_tags("library/alpine") == ["3.23.5"]
      assert Artifacts.docker_tags("hexpm/erlang-amd64") == [{"untouched", ["amd64"]}]
    end
  end

  describe "import_otp_builds/0" do
    test "imports OTP builds.txt without touching docker tags" do
      Bob.FakeHttpClient.reset()

      Bob.FakeHttpClient.stub(
        :get,
        "https://s3.amazonaws.com/s3.hex.pm/builds/otp/amd64/ubuntu-24.04/builds.txt",
        200,
        "OTP-27.0 ref27 2026-01-02T03:04:05Z sha27\nOTP-26.0 ref26 2026-01-02T03:04:05Z\n"
      )

      Reconcile.import_otp_builds()

      assert Artifacts.built_otp_refs("amd64", "ubuntu-24.04") == %{
               "OTP-27.0" => "ref27",
               "OTP-26.0" => "ref26"
             }
    end
  end

  describe "backfill/1" do
    test "imports OTP builds.txt into build_artifacts in addition to reconciling" do
      Bob.FakeHttpClient.reset()

      Bob.FakeHttpClient.stub(
        :get,
        "https://s3.amazonaws.com/s3.hex.pm/builds/otp/amd64/ubuntu-24.04/builds.txt",
        200,
        "OTP-27.0 ref27 2026-01-02T03:04:05Z sha27\nOTP-26.0 ref26 2026-01-02T03:04:05Z\n"
      )

      Reconcile.backfill(streamer(%{}))

      assert Artifacts.built_otp_refs("amd64", "ubuntu-24.04") == %{
               "OTP-27.0" => "ref27",
               "OTP-26.0" => "ref26"
             }
    end

    test "skips malformed builds.txt lines without raising" do
      Bob.FakeHttpClient.reset()

      Bob.FakeHttpClient.stub(
        :get,
        "https://s3.amazonaws.com/s3.hex.pm/builds/otp/amd64/ubuntu-24.04/builds.txt",
        200,
        "OTP-27.0 ref27 2026-01-02T03:04:05Z sha27\ngarbage line\n"
      )

      Reconcile.backfill(streamer(%{}))

      assert Artifacts.built_otp_refs("amd64", "ubuntu-24.04") == %{"OTP-27.0" => "ref27"}
    end
  end

  defp docker_tag(tag, archs, built_at \\ @docker_built_at), do: {tag, archs, built_at}
end
