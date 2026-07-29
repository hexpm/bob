defmodule Bob.DockerCleanupTest do
  use Bob.DataCase

  alias Bob.{Artifacts, BuildRequests, DockerCleanup}

  defp days_ago(days), do: DateTime.add(DateTime.utc_now(), -days, :day)
  defp old(), do: days_ago(40)
  defp ancient(), do: days_ago(250)
  defp recent(), do: days_ago(10)

  describe "removal_at/2" do
    test "per-arch tags expire 30 days after build" do
      built = ~U[2026-01-01 00:00:00Z]

      assert DockerCleanup.removal_at("hexpm/erlang-amd64", built) ==
               DateTime.add(built, 30, :day)

      assert DockerCleanup.removal_at("hexpm/elixir-arm64", built) ==
               DateTime.add(built, 30, :day)
    end

    test "returns nil for a repo not under cleanup, including the manifest repos" do
      built = ~U[2026-01-01 00:00:00Z]

      assert DockerCleanup.removal_at("library/alpine", built) == nil
      assert DockerCleanup.removal_at("hexpm/erlang", built) == nil
      assert DockerCleanup.removal_at("hexpm/elixir", built) == nil
    end
  end

  describe "run/1 in dry-run mode" do
    test "returns the counts a live run would delete, deleting nothing" do
      Artifacts.add_docker_tag(
        "hexpm/erlang-amd64",
        "26.0-ubuntu-noble-20250101",
        ["amd64"],
        old()
      )

      assert {:dry_run, %{per_arch: per_arch}} = DockerCleanup.run(mode: :dry_run)

      assert per_arch == %{"hexpm/erlang-amd64" => 1}

      assert Artifacts.docker_tags("hexpm/erlang-amd64") ==
               [{"26.0-ubuntu-noble-20250101", ["amd64"]}]
    end
  end

  describe "run/1 in live mode" do
    test "deletes stale tags via the deleter and drops their rows, keeping recent and reserved" do
      test = self()

      deleter = fn repo, tag ->
        send(test, {:deleted, repo, tag})
        :ok
      end

      # stale, not reserved -> deleted
      Artifacts.add_docker_tag(
        "hexpm/erlang-amd64",
        "26.0-ubuntu-noble-20250101",
        ["amd64"],
        old()
      )

      # recent -> kept
      Artifacts.add_docker_tag(
        "hexpm/erlang-amd64",
        "28.0-ubuntu-noble-20250101",
        ["amd64"],
        recent()
      )

      # stale but reserved -> kept
      Artifacts.add_docker_tag(
        "hexpm/erlang-amd64",
        "27.0-ubuntu-noble-20250101",
        ["amd64"],
        old()
      )

      BuildRequests.create(%{
        username: "eric",
        kind: "erlang",
        erlang: "27.0",
        os: "ubuntu",
        os_version: "noble-20250101",
        builds_count: 0
      })

      # ancient manifest tag -> kept; manifest repos are never pruned
      Artifacts.add_docker_tag(
        "hexpm/erlang",
        "25.0-ubuntu-noble-20250101",
        ["amd64", "arm64"],
        ancient()
      )

      assert {:live, 1} = DockerCleanup.run(mode: :live, deleter: deleter)

      assert_received {:deleted, "hexpm/erlang-amd64", "26.0-ubuntu-noble-20250101"}
      refute_received {:deleted, "hexpm/erlang", _tag}
      refute_received {:deleted, "hexpm/erlang-amd64", "27.0-ubuntu-noble-20250101"}
      refute_received {:deleted, "hexpm/erlang-amd64", "28.0-ubuntu-noble-20250101"}

      assert Enum.sort(Artifacts.docker_tags("hexpm/erlang-amd64")) ==
               Enum.sort([
                 {"27.0-ubuntu-noble-20250101", ["amd64"]},
                 {"28.0-ubuntu-noble-20250101", ["amd64"]}
               ])

      assert Artifacts.docker_tags("hexpm/erlang") ==
               [{"25.0-ubuntu-noble-20250101", ["amd64", "arm64"]}]
    end

    test "skips a tag that was reserved after the candidates were selected" do
      test = self()

      # The rate-limited batch can run for hours after the candidate list is
      # built. Reserving every candidate while the first is deleted simulates a
      # user requesting an image mid-run: the remaining tag must survive.
      deleter = fn repo, tag ->
        send(test, {:deleted, repo, tag})

        for erlang <- ["26.0", "27.0"] do
          BuildRequests.create(%{
            username: "eric",
            kind: "erlang",
            erlang: erlang,
            os: "ubuntu",
            os_version: "noble-20250101",
            builds_count: 0
          })
        end

        :ok
      end

      for erlang <- ["26.0", "27.0"] do
        Artifacts.add_docker_tag(
          "hexpm/erlang-amd64",
          "#{erlang}-ubuntu-noble-20250101",
          ["amd64"],
          old()
        )
      end

      assert {:live, 1} = DockerCleanup.run(mode: :live, deleter: deleter)

      assert_received {:deleted, "hexpm/erlang-amd64", _tag}
      refute_received {:deleted, _repo, _tag}
      assert length(Artifacts.docker_tags("hexpm/erlang-amd64")) == 1
    end

    test "keeps the row when deletion errors" do
      deleter = fn _repo, _tag -> {:error, :boom} end

      Artifacts.add_docker_tag(
        "hexpm/erlang-amd64",
        "26.0-ubuntu-noble-20250101",
        ["amd64"],
        old()
      )

      assert {:live, 0} = DockerCleanup.run(mode: :live, deleter: deleter)

      assert Artifacts.docker_tags("hexpm/erlang-amd64") ==
               [{"26.0-ubuntu-noble-20250101", ["amd64"]}]
    end

    test "respects the batch limit so a run deletes a bounded slice" do
      deleter = fn _repo, _tag -> :ok end

      for n <- 1..3 do
        Artifacts.add_docker_tag(
          "hexpm/erlang-amd64",
          "2#{n}.0-ubuntu-noble-20250101",
          ["amd64"],
          old()
        )
      end

      assert {:live, 2} = DockerCleanup.run(mode: :live, deleter: deleter, limit: 2)
      assert length(Artifacts.docker_tags("hexpm/erlang-amd64")) == 1
    end

    test "an ancient manifest tag is never a candidate, whatever the limit" do
      deleter = fn _repo, _tag -> :ok end

      Artifacts.add_docker_tag(
        "hexpm/erlang",
        "25.0-ubuntu-noble-20250101",
        ["amd64", "arm64"],
        ancient()
      )

      assert {:live, 0} = DockerCleanup.run(mode: :live, deleter: deleter, limit: 100)

      assert Artifacts.docker_tags("hexpm/erlang") ==
               [{"25.0-ubuntu-noble-20250101", ["amd64", "arm64"]}]
    end
  end

  describe "retention windows" do
    # The checker's expected set is filtered on release recency while cleanup
    # filters on build dates, and a tag is always built after the release that
    # triggered it. Once the cleanup window is shorter than the checker's, every
    # run deletes tags the checker still expects and queues them for rebuild.
    test "per-arch retention is at least the checker's build freshness window" do
      assert DockerCleanup.per_arch_max_age_days() >=
               Bob.Job.DockerChecker.build_freshness_days()
    end
  end
end
