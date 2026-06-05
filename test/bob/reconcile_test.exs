defmodule Bob.ReconcileTest do
  use Bob.DataCase

  alias Bob.{Artifacts, Reconcile}

  # Fetcher stub: returns canned {tag, archs} lists keyed by repo, [] otherwise.
  defp fetcher(map) do
    fn repo -> Map.get(map, repo, []) end
  end

  describe "reconcile/1" do
    test "stores per-arch erlang/elixir tags with the arch forced from the repo name" do
      fetch =
        fetcher(%{
          "hexpm/erlang-amd64" => [{"27.0-ubuntu-noble-20250101", ["amd64", "arm64"]}],
          "hexpm/elixir-arm64" => [{"1.18.0-erlang-27.0-ubuntu-noble-20250101", ["amd64"]}]
        })

      Reconcile.reconcile(fetch)

      assert Artifacts.docker_tags("hexpm/erlang-amd64") ==
               [{"27.0-ubuntu-noble-20250101", ["amd64"]}]

      assert Artifacts.docker_tags("hexpm/elixir-arm64") ==
               [{"1.18.0-erlang-27.0-ubuntu-noble-20250101", ["arm64"]}]
    end

    test "stores manifest tags with the upstream archs intersected with known archs, sorted" do
      fetch =
        fetcher(%{
          "hexpm/erlang" => [{"27.0-ubuntu-noble-20250101", ["arm64", "amd64", "ppc64le"]}]
        })

      Reconcile.reconcile(fetch)

      assert Artifacts.docker_tags("hexpm/erlang") ==
               [{"27.0-ubuntu-noble-20250101", ["amd64", "arm64"]}]
    end

    test "stores only fully-multi-arch base image tags" do
      fetch =
        fetcher(%{
          "library/alpine" => [
            {"3.23.5", ["amd64", "arm64", "386"]},
            {"3.22.1", ["amd64"]}
          ]
        })

      Reconcile.reconcile(fetch)

      assert Artifacts.base_image_tags("library/alpine") == ["3.23.5"]
    end

    test "prunes docker tags that vanished upstream" do
      Artifacts.add_docker_tag("hexpm/erlang-amd64", "stale-tag", ["amd64"])

      fetch = fetcher(%{"hexpm/erlang-amd64" => [{"fresh-tag", ["amd64"]}]})

      Reconcile.reconcile(fetch)

      assert Artifacts.docker_tags("hexpm/erlang-amd64") == [{"fresh-tag", ["amd64"]}]
    end

    test "skips a repo whose fetch returns empty, leaving existing rows untouched" do
      Artifacts.add_docker_tag("hexpm/erlang-amd64", "keep-me", ["amd64"])

      Reconcile.reconcile(fetcher(%{}))

      assert Artifacts.docker_tags("hexpm/erlang-amd64") == [{"keep-me", ["amd64"]}]
    end

    test "skips a repo whose fetch fails without wiping its rows or aborting siblings" do
      Artifacts.add_docker_tag("hexpm/erlang-amd64", "keep-me", ["amd64"])

      fetch = fn
        "hexpm/erlang-amd64" -> raise "DockerHub paging failed for hexpm/erlang-amd64"
        "hexpm/elixir-arm64" -> [{"fresh-tag", ["arm64"]}]
        _repo -> []
      end

      Reconcile.reconcile(fetch)

      assert Artifacts.docker_tags("hexpm/erlang-amd64") == [{"keep-me", ["amd64"]}]
      assert Artifacts.docker_tags("hexpm/elixir-arm64") == [{"fresh-tag", ["arm64"]}]
    end
  end

  describe "backfill/1" do
    test "imports OTP builds.txt into build_artifacts in addition to reconciling" do
      Bob.FakeHttpClient.reset()

      Bob.FakeHttpClient.stub(
        :get,
        "https://s3.amazonaws.com/s3.hex.pm/builds/otp/amd64/ubuntu-24.04/builds.txt",
        200,
        "OTP-27.0 ref27 2026-01-02T03:04:05Z sha27\nOTP-26.0 ref26 2026-01-02T03:04:05Z sha26\n"
      )

      Reconcile.backfill(fetcher(%{}))

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

      Reconcile.backfill(fetcher(%{}))

      assert Artifacts.built_otp_refs("amd64", "ubuntu-24.04") == %{"OTP-27.0" => "ref27"}
    end
  end
end
