defmodule Bob.DockerCleanupTest do
  use Bob.DataCase

  alias Bob.{Artifacts, BuildRequests, DockerCleanup}

  # Mirrors Bob.DockerCleanup's own chunk size so these exercise real boundaries.
  @chunk 100

  defp days_ago(days), do: DateTime.add(DateTime.utc_now(), -days, :day)
  defp old(), do: days_ago(40)
  defp ancient(), do: days_ago(250)
  defp recent(), do: days_ago(10)

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

    test "a tag reserved during a run is spared from the next chunk" do
      tags = add_stale_tags("hexpm/elixir-amd64", @chunk + 50)

      # Reserve every tag while the first chunk is being deleted. That chunk was
      # already re-checked so it goes, but the next one must find them pinned.
      deleter = fn _repo, _tag ->
        unless Process.get(:reserved) do
          Process.put(:reserved, true)
          reserve_targets(tags)
        end

        :ok
      end

      assert {:live, @chunk} = DockerCleanup.run(mode: :live, deleter: deleter)
      assert length(Artifacts.docker_tags("hexpm/elixir-amd64")) == 50
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
    test "rows are dropped as the batch progresses, not only at the end" do
      test = self()
      add_stale_tags("hexpm/elixir-amd64", @chunk + 50)

      deleter = fn repo, _tag ->
        send(test, {:remaining, length(Artifacts.docker_tags(repo))})
        :ok
      end

      assert {:live, total} = DockerCleanup.run(mode: :live, deleter: deleter)
      assert total == @chunk + 50

      # Committing only at the end would report the full count throughout.
      assert Enum.min(received_remaining()) == 50
      assert Artifacts.docker_tags("hexpm/elixir-amd64") == []
    end

    test "a tag re-pushed mid-run is no longer deletable" do
      tags = add_stale_tags("hexpm/elixir-amd64", @chunk + 50)

      # Reconcile bumping built_at while the first chunk is being deleted.
      deleter = fn repo, _tag ->
        unless Process.get(:repushed) do
          Process.put(:repushed, true)
          for tag <- tags, do: Artifacts.add_docker_tag(repo, tag, ["amd64"], DateTime.utc_now())
        end

        :ok
      end

      assert {:live, @chunk} = DockerCleanup.run(mode: :live, deleter: deleter)
      assert length(Artifacts.docker_tags("hexpm/elixir-amd64")) == 50
    end

    test "a run where every delete fails aborts instead of walking the batch" do
      test = self()
      add_stale_tags("hexpm/elixir-amd64", @chunk * 5)

      deleter = fn _repo, _tag ->
        send(test, :attempted)
        {:error, :unauthorized}
      end

      assert {:live, 0} = DockerCleanup.run(mode: :live, deleter: deleter)

      # Stops after @dead_chunk_ceiling chunks rather than walking all five.
      assert count_received(:attempted) == @chunk * 3
      assert length(Artifacts.docker_tags("hexpm/elixir-amd64")) == @chunk * 5
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

  # Bulk insert: these tests need more rows than one chunk, and add_docker_tag/4
  # a few hundred times dominates the runtime.
  defp add_stale_tags(repo, count) do
    now = DateTime.utc_now()
    built_at = old()

    rows =
      for n <- 1..count do
        %{
          repo: repo,
          tag: "1.#{n}.0-erlang-27.0-ubuntu-noble-20250101",
          archs: ["amd64"],
          search: %{},
          built_at: built_at,
          inserted_at: now,
          updated_at: now
        }
      end

    Repo.insert_all(Bob.Artifacts.DockerTag, rows)
    Enum.map(rows, & &1.tag)
  end

  defp reserve_targets(tags) do
    now = DateTime.utc_now()

    rows =
      for tag <- tags do
        [elixir, erlang, os, os_version] =
          Regex.run(~r/^(.+)-erlang-(.+)-(alpine|ubuntu|debian)-(.+)$/, tag,
            capture: :all_but_first
          )

        %{
          username: "eric",
          kind: "elixir",
          elixir: elixir,
          erlang: erlang,
          os: os,
          os_version: os_version,
          builds_count: 0,
          state: "completed",
          inserted_at: now,
          updated_at: now
        }
      end

    Repo.insert_all(Bob.BuildRequests.BuildRequest, rows)
  end

  defp received_remaining() do
    Enum.flat_map(drain_mailbox(), fn
      {:remaining, n} -> [n]
      _other -> []
    end)
  end

  defp count_received(msg), do: Enum.count(drain_mailbox(), &(&1 == msg))

  defp drain_mailbox() do
    Stream.repeatedly(fn ->
      receive do
        m -> m
      after
        0 -> :__empty__
      end
    end)
    |> Enum.take_while(&(&1 != :__empty__))
  end

  defp drain_messages(take) do
    Stream.repeatedly(fn ->
      receive do
        m -> m
      after
        0 -> :done
      end
    end)
    |> Enum.take_while(&(&1 != :done))
    |> Enum.map(fn
      {:remaining, n} -> n
      other -> other
    end)
    |> tap(fn _ -> take end)
  end
end
