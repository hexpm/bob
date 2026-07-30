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

      assert DockerCleanup.removal_at("hexpm/elixir-amd64", built) ==
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
        "hexpm/elixir-amd64",
        "1.26.0-erlang-27.0-ubuntu-noble-20250101",
        ["amd64"],
        old()
      )

      assert {:dry_run, %{per_arch: per_arch}} = DockerCleanup.run(mode: :dry_run)

      assert per_arch == %{"hexpm/elixir-amd64" => 1}

      assert Artifacts.docker_tags("hexpm/elixir-amd64") ==
               [{"1.26.0-erlang-27.0-ubuntu-noble-20250101", ["amd64"]}]
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
        "hexpm/elixir-amd64",
        "1.26.0-erlang-27.0-ubuntu-noble-20250101",
        ["amd64"],
        old()
      )

      # recent -> kept
      Artifacts.add_docker_tag(
        "hexpm/elixir-amd64",
        "1.28.0-erlang-27.0-ubuntu-noble-20250101",
        ["amd64"],
        recent()
      )

      # stale but reserved -> kept
      Artifacts.add_docker_tag(
        "hexpm/elixir-amd64",
        "1.27.0-erlang-27.0-ubuntu-noble-20250101",
        ["amd64"],
        old()
      )

      BuildRequests.create(%{
        username: "eric",
        kind: "elixir",
        elixir: "1.27.0",
        erlang: "27.0",
        os: "ubuntu",
        os_version: "noble-20250101",
        builds_count: 0
      })

      # ancient manifest tag -> kept; manifest repos are never pruned
      Artifacts.add_docker_tag(
        "hexpm/elixir",
        "1.25.0-erlang-27.0-ubuntu-noble-20250101",
        ["amd64", "arm64"],
        ancient()
      )

      assert {:live, 1} = DockerCleanup.run(mode: :live, deleter: deleter)

      assert_received {:deleted, "hexpm/elixir-amd64", "1.26.0-erlang-27.0-ubuntu-noble-20250101"}
      refute_received {:deleted, "hexpm/elixir", _tag}
      refute_received {:deleted, "hexpm/elixir-amd64", "1.27.0-erlang-27.0-ubuntu-noble-20250101"}
      refute_received {:deleted, "hexpm/elixir-amd64", "1.28.0-erlang-27.0-ubuntu-noble-20250101"}

      assert Enum.sort(Artifacts.docker_tags("hexpm/elixir-amd64")) ==
               Enum.sort([
                 {"1.27.0-erlang-27.0-ubuntu-noble-20250101", ["amd64"]},
                 {"1.28.0-erlang-27.0-ubuntu-noble-20250101", ["amd64"]}
               ])

      assert Artifacts.docker_tags("hexpm/elixir") ==
               [{"1.25.0-erlang-27.0-ubuntu-noble-20250101", ["amd64", "arm64"]}]
    end

    test "skips a tag that was reserved after the candidates were selected" do
      test = self()

      # The rate-limited batch can run for hours after the candidate list is
      # built. Reserving every candidate while the first is deleted simulates a
      # user requesting an image mid-run: the remaining tag must survive.
      deleter = fn repo, tag ->
        send(test, {:deleted, repo, tag})

        for elixir <- ["1.26.0", "1.27.0"] do
          BuildRequests.create(%{
            username: "eric",
            kind: "elixir",
            elixir: elixir,
            erlang: "27.0",
            os: "ubuntu",
            os_version: "noble-20250101",
            builds_count: 0
          })
        end

        :ok
      end

      for elixir <- ["1.26.0", "1.27.0"] do
        Artifacts.add_docker_tag(
          "hexpm/elixir-amd64",
          "#{elixir}-erlang-27.0-ubuntu-noble-20250101",
          ["amd64"],
          old()
        )
      end

      assert {:live, 1} =
               DockerCleanup.run(mode: :live, deleter: deleter, chunk: 1, concurrency: 1)

      assert_received {:deleted, "hexpm/elixir-amd64", _tag}
      refute_received {:deleted, _repo, _tag}
      assert length(Artifacts.docker_tags("hexpm/elixir-amd64")) == 1
    end

    test "keeps the row when deletion errors" do
      deleter = fn _repo, _tag -> {:error, :boom} end

      Artifacts.add_docker_tag(
        "hexpm/elixir-amd64",
        "1.26.0-erlang-27.0-ubuntu-noble-20250101",
        ["amd64"],
        old()
      )

      assert {:live, 0} = DockerCleanup.run(mode: :live, deleter: deleter)

      assert Artifacts.docker_tags("hexpm/elixir-amd64") ==
               [{"1.26.0-erlang-27.0-ubuntu-noble-20250101", ["amd64"]}]
    end

    test "respects the batch limit so a run deletes a bounded slice" do
      deleter = fn _repo, _tag -> :ok end

      for n <- 1..3 do
        Artifacts.add_docker_tag(
          "hexpm/elixir-amd64",
          "2#{n}.0-ubuntu-noble-20250101",
          ["amd64"],
          old()
        )
      end

      assert {:live, 2} = DockerCleanup.run(mode: :live, deleter: deleter, limit: 2)
      assert length(Artifacts.docker_tags("hexpm/elixir-amd64")) == 1
    end

    test "an ancient manifest tag is never a candidate, whatever the limit" do
      deleter = fn _repo, _tag -> :ok end

      Artifacts.add_docker_tag(
        "hexpm/elixir",
        "1.25.0-erlang-27.0-ubuntu-noble-20250101",
        ["amd64", "arm64"],
        ancient()
      )

      assert {:live, 0} = DockerCleanup.run(mode: :live, deleter: deleter, limit: 100)

      assert Artifacts.docker_tags("hexpm/elixir") ==
               [{"1.25.0-erlang-27.0-ubuntu-noble-20250101", ["amd64", "arm64"]}]
    end
  end

  describe "run/1 durability" do
    # A killed run (the three-hour job timeout, a rolling deploy, an OOM) must
    # leave docker_tags agreeing with Docker Hub for everything deleted so far.
    # Committing only at the end meant the next run re-issued every delete,
    # spent the rate limit on 404s, and made no progress either.
    test "rows are dropped as the batch progresses, not only at the end" do
      test = self()

      # Reports how many rows survive at the moment each delete runs. With
      # per-chunk commits that count falls as the run proceeds; committing only
      # at the end would report the full count every time, which is exactly the
      # bug that let a killed run lose all its work.
      deleter = fn repo, _tag ->
        send(test, {:remaining, length(Artifacts.docker_tags(repo))})
        :ok
      end

      for n <- 1..4 do
        Artifacts.add_docker_tag(
          "hexpm/elixir-amd64",
          "1.2#{n}.0-erlang-27.0-ubuntu-noble-20250101",
          ["amd64"],
          old()
        )
      end

      assert {:live, 4} =
               DockerCleanup.run(
                 mode: :live,
                 deleter: deleter,
                 limit: 10,
                 chunk: 1,
                 concurrency: 1
               )

      assert_received {:remaining, 4}
      assert_received {:remaining, 3}
      assert_received {:remaining, 2}
      assert_received {:remaining, 1}
      assert Artifacts.docker_tags("hexpm/elixir-amd64") == []
    end

    test "a tag re-pushed mid-run is no longer deletable" do
      test = self()

      # Simulates the nightly reconcile bumping built_at from Docker Hub while a
      # long batch is still working through candidates selected before it.
      tags =
        for n <- 1..2, do: "1.2#{n}.0-erlang-27.0-ubuntu-noble-20250101"

      for tag <- tags do
        Artifacts.add_docker_tag("hexpm/elixir-amd64", tag, ["amd64"], old())
      end

      # Re-pushes whichever tag is not the one currently being deleted, so the
      # assertion holds whatever order the candidate query returned.
      deleter = fn repo, tag ->
        send(test, {:deleted, tag})
        other = Enum.find(tags, &(&1 != tag))
        Artifacts.add_docker_tag(repo, other, ["amd64"], DateTime.utc_now())
        :ok
      end

      assert {:live, 1} =
               DockerCleanup.run(mode: :live, deleter: deleter, chunk: 1, concurrency: 1)

      assert_received {:deleted, _first}
      refute_received {:deleted, _second}
      assert length(Artifacts.docker_tags("hexpm/elixir-amd64")) == 1
    end

    # A token without delete permission 401s on every candidate. Without a
    # ceiling that is hours of full-rate Docker Hub traffic, nightly.
    test "a run where every delete fails aborts instead of walking the batch" do
      test = self()

      deleter = fn _repo, _tag ->
        send(test, :attempted)
        {:error, :unauthorized}
      end

      for n <- 1..40 do
        Artifacts.add_docker_tag(
          "hexpm/elixir-amd64",
          "1.#{n}.0-erlang-27.0-ubuntu-noble-20250101",
          ["amd64"],
          old()
        )
      end

      assert {:live, 0} = DockerCleanup.run(mode: :live, deleter: deleter, chunk: 10)

      attempts =
        Enum.count(
          Stream.repeatedly(fn -> nil end)
          |> Enum.take_while(fn _ ->
            receive do
              :attempted -> true
            after
              0 -> false
            end
          end)
        )

      assert attempts < 40
      assert length(Artifacts.docker_tags("hexpm/elixir-amd64")) == 40
    end
  end

  describe "drain/1" do
    test "keeps going past the batch limit until nothing is left" do
      deleter = fn _repo, _tag -> :ok end

      for n <- 1..7 do
        Artifacts.add_docker_tag(
          "hexpm/elixir-amd64",
          "1.#{n}.0-erlang-27.0-ubuntu-noble-20250101",
          ["amd64"],
          old()
        )
      end

      # A single run of this batch size would stop at 2; the drain loops.
      assert DockerCleanup.drain(limit: 2, deleter: deleter) == 7
      assert Artifacts.docker_tags("hexpm/elixir-amd64") == []
    end

    test "stops rather than spinning when a tag cannot be deleted" do
      deleter = fn _repo, _tag -> {:error, :nope} end

      Artifacts.add_docker_tag(
        "hexpm/elixir-amd64",
        "1.18.0-erlang-27.0-ubuntu-noble-20250101",
        ["amd64"],
        old()
      )

      assert DockerCleanup.drain(deleter: deleter) == 0
      assert length(Artifacts.docker_tags("hexpm/elixir-amd64")) == 1
    end

    test "leaves reserved and recent tags alone" do
      deleter = fn _repo, _tag -> :ok end

      Artifacts.add_docker_tag(
        "hexpm/elixir-amd64",
        "1.18.0-erlang-27.0-ubuntu-noble-20250101",
        ["amd64"],
        recent()
      )

      Artifacts.add_docker_tag(
        "hexpm/elixir-amd64",
        "1.19.0-erlang-27.0-ubuntu-noble-20250101",
        ["amd64"],
        old()
      )

      BuildRequests.create(%{
        username: "eric",
        kind: "elixir",
        elixir: "1.19.0",
        erlang: "27.0",
        os: "ubuntu",
        os_version: "noble-20250101",
        builds_count: 0
      })

      assert DockerCleanup.drain(limit: 2, deleter: deleter) == 0
      assert length(Artifacts.docker_tags("hexpm/elixir-amd64")) == 2
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
