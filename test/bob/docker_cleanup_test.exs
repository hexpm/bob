defmodule Bob.DockerCleanupTest do
  use Bob.DataCase

  alias Bob.{Artifacts, BuildRequests, DockerCleanup}

  defp days_ago(days), do: DateTime.add(DateTime.utc_now(), -days, :day)
  defp old(), do: days_ago(40)
  defp ancient(), do: days_ago(250)
  defp recent(), do: days_ago(10)

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
        recent(),
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
        recent(),
        ancient()
      )

      assert {:live, 2} = DockerCleanup.run(mode: :live, deleter: deleter)

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
  end
end
