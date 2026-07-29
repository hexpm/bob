defmodule Bob.DockerCleanupTest do
  use Bob.DataCase

  alias Bob.{Artifacts, BuildRequests, DockerCleanup}

  defp days_ago(days), do: DateTime.add(DateTime.utc_now(), -days, :day)
  defp old(), do: days_ago(40)
  defp ancient(), do: days_ago(250)
  defp recent(), do: days_ago(10)

  describe "removal_at/3" do
    test "per-arch tags expire 30 days after build, ignoring last_pulled" do
      built = ~U[2026-01-01 00:00:00Z]

      assert DockerCleanup.removal_at("hexpm/erlang-amd64", built, nil) ==
               DateTime.add(built, 30, :day)

      assert DockerCleanup.removal_at("hexpm/elixir-arm64", built, ~U[2026-06-01 00:00:00Z]) ==
               DateTime.add(built, 30, :day)
    end

    test "manifest tags expire 180 days after last pull, falling back to build" do
      built = ~U[2026-01-01 00:00:00Z]
      pulled = ~U[2026-03-01 00:00:00Z]

      assert DockerCleanup.removal_at("hexpm/erlang", built, pulled) ==
               DateTime.add(pulled, 180, :day)

      assert DockerCleanup.removal_at("hexpm/elixir", built, nil) ==
               DateTime.add(built, 180, :day)
    end

    test "manifest tags rebuilt after their last pull expire from the rebuild" do
      built = ~U[2026-05-01 00:00:00Z]
      pulled = ~U[2026-01-01 00:00:00Z]

      assert DockerCleanup.removal_at("hexpm/erlang", built, pulled) ==
               DateTime.add(built, 180, :day)
    end

    test "returns nil for a repo not under cleanup" do
      assert DockerCleanup.removal_at("library/alpine", ~U[2026-01-01 00:00:00Z], nil) == nil
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

      Artifacts.add_docker_tag(
        "hexpm/erlang",
        "25.0-ubuntu-noble-20250101",
        ["amd64", "arm64"],
        ancient(),
        ancient()
      )

      assert {:dry_run, %{per_arch: per_arch, manifest: manifest}} =
               DockerCleanup.run(mode: :dry_run)

      assert per_arch == %{"hexpm/erlang-amd64" => 1}
      assert manifest == %{"hexpm/erlang" => 1}

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

      # stale manifest -> deleted
      Artifacts.add_docker_tag(
        "hexpm/erlang",
        "25.0-ubuntu-noble-20250101",
        ["amd64", "arm64"],
        ancient(),
        ancient()
      )

      assert {:live, 2} =
               DockerCleanup.run(mode: :live, deleter: deleter, scope: [:per_arch, :manifest])

      assert_received {:deleted, "hexpm/erlang-amd64", "26.0-ubuntu-noble-20250101"}
      assert_received {:deleted, "hexpm/erlang", "25.0-ubuntu-noble-20250101"}
      refute_received {:deleted, "hexpm/erlang-amd64", "27.0-ubuntu-noble-20250101"}
      refute_received {:deleted, "hexpm/erlang-amd64", "28.0-ubuntu-noble-20250101"}

      assert Enum.sort(Artifacts.docker_tags("hexpm/erlang-amd64")) ==
               Enum.sort([
                 {"27.0-ubuntu-noble-20250101", ["amd64"]},
                 {"28.0-ubuntu-noble-20250101", ["amd64"]}
               ])

      assert Artifacts.docker_tags("hexpm/erlang") == []
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

    test "the batch limit bounds the whole run across both repo groups" do
      deleter = fn _repo, _tag -> :ok end

      for n <- 1..2 do
        Artifacts.add_docker_tag(
          "hexpm/erlang-amd64",
          "2#{n}.0-ubuntu-noble-20250101",
          ["amd64"],
          old()
        )

        Artifacts.add_docker_tag(
          "hexpm/erlang",
          "2#{n}.1-ubuntu-noble-20250101",
          ["amd64", "arm64"],
          ancient(),
          ancient()
        )
      end

      assert {:live, 3} =
               DockerCleanup.run(
                 mode: :live,
                 deleter: deleter,
                 limit: 3,
                 scope: [:per_arch, :manifest]
               )
    end
  end

  describe "run/1 scope" do
    setup do
      test = self()

      deleter = fn repo, tag ->
        send(test, {:deleted, repo, tag})
        :ok
      end

      Artifacts.add_docker_tag(
        "hexpm/erlang-amd64",
        "26.0-ubuntu-noble-20250101",
        ["amd64"],
        old()
      )

      Artifacts.add_docker_tag(
        "hexpm/erlang",
        "25.0-ubuntu-noble-20250101",
        ["amd64", "arm64"],
        ancient(),
        ancient()
      )

      %{deleter: deleter}
    end

    test "defaults to per-arch only, leaving the manifest repos alone", %{deleter: deleter} do
      assert {:live, 1} = DockerCleanup.run(mode: :live, deleter: deleter)

      assert_received {:deleted, "hexpm/erlang-amd64", _tag}
      refute_received {:deleted, "hexpm/erlang", _tag}

      assert Artifacts.docker_tags("hexpm/erlang-amd64") == []
      assert [{"25.0-ubuntu-noble-20250101", _archs}] = Artifacts.docker_tags("hexpm/erlang")
    end

    # The limit budgets the run but must not confine it: once the per-arch
    # backlog falls under the limit, a scope-less implementation would start
    # spending the remainder on manifest repos without anyone changing config.
    test "a limit larger than the per-arch backlog does not spill into manifests", %{
      deleter: deleter
    } do
      assert {:live, 1} = DockerCleanup.run(mode: :live, deleter: deleter, limit: 100)

      refute_received {:deleted, "hexpm/erlang", _tag}
    end

    test "manifest scope deletes only from the manifest repos", %{deleter: deleter} do
      assert {:live, 1} = DockerCleanup.run(mode: :live, deleter: deleter, scope: [:manifest])

      assert_received {:deleted, "hexpm/erlang", _tag}
      refute_received {:deleted, "hexpm/erlang-amd64", _tag}
    end

    test "an empty scope deletes nothing", %{deleter: deleter} do
      assert {:live, 0} = DockerCleanup.run(mode: :live, deleter: deleter, scope: [])

      refute_received {:deleted, _repo, _tag}
    end

    test "unknown scopes are dropped rather than widening the run" do
      Application.put_env(:bob, :docker_cleanup_scope, [:per_arch, :everything])
      on_exit(fn -> Application.put_env(:bob, :docker_cleanup_scope, [:per_arch]) end)

      assert DockerCleanup.configured_scope() == [:per_arch]
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

    test "manifest retention outlives per-arch retention" do
      assert DockerCleanup.manifest_unpulled_days() > DockerCleanup.per_arch_max_age_days()
    end
  end
end
