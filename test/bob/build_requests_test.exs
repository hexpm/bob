defmodule Bob.BuildRequestsTest do
  use Bob.DataCase

  alias Bob.Artifacts
  alias Bob.BuildRequests
  alias Bob.BuildRequests.BuildRequest
  alias Bob.Queue.Job

  @erlang_attrs %{
    username: "eric",
    kind: "erlang",
    erlang: "27.0",
    os: "ubuntu",
    os_version: "noble-20250101"
  }

  @elixir_attrs %{
    username: "eric",
    kind: "elixir",
    elixir: "1.18.0",
    erlang: "27.0",
    os: "ubuntu",
    os_version: "noble-20250101"
  }

  describe "submit/1 with an erlang request" do
    test "enqueues a build per missing arch and records the request" do
      assert {:ok, %BuildRequest{} = request} = submit(@erlang_attrs)

      assert request.builds_count == 2
      assert request.state == "pending"

      jobs = Repo.all(Job) |> Enum.map(&{&1.module_key, &1.args}) |> Enum.sort()

      assert jobs ==
               Enum.sort([
                 {{Bob.Job.BuildDockerErlang, "amd64"}, ["27.0", "ubuntu", "noble-20250101"]},
                 {{Bob.Job.BuildDockerErlang, "arm64"}, ["27.0", "ubuntu", "noble-20250101"]}
               ])
    end

    test "enqueues only the missing arch" do
      Artifacts.add_docker_tag("hexpm/erlang-amd64", "27.0-ubuntu-noble-20250101", ["amd64"])

      assert {:ok, %BuildRequest{builds_count: 1}} = submit(@erlang_attrs)

      assert [%Job{module_key: {Bob.Job.BuildDockerErlang, "arm64"}}] = Repo.all(Job)
    end

    test "reports already built tags without recording a request" do
      Artifacts.add_docker_tag("hexpm/erlang-amd64", "27.0-ubuntu-noble-20250101", ["amd64"])
      Artifacts.add_docker_tag("hexpm/erlang-arm64", "27.0-ubuntu-noble-20250101", ["arm64"])

      assert BuildRequests.submit(@erlang_attrs) == {:ok, :already_built}
      assert Repo.all(Job) == []
      assert Repo.all(BuildRequest) == []
    end

    test "rejects combinations the build rules reject" do
      attrs = %{@erlang_attrs | erlang: "24.1"}

      assert BuildRequests.submit(attrs) == {:error, :invalid_combo}
      assert Repo.all(Job) == []
      assert Repo.all(BuildRequest) == []
    end
  end

  describe "submit/1 with an elixir request" do
    test "enqueues the elixir builds when the erlang base exists" do
      Artifacts.add_docker_tag("hexpm/erlang-amd64", "27.0-ubuntu-noble-20250101", ["amd64"])
      Artifacts.add_docker_tag("hexpm/erlang-arm64", "27.0-ubuntu-noble-20250101", ["arm64"])

      assert {:ok, %BuildRequest{builds_count: 2}} = submit(@elixir_attrs)

      jobs = Repo.all(Job) |> Enum.map(&{&1.module_key, &1.args}) |> Enum.sort()

      assert jobs ==
               Enum.sort([
                 {{Bob.Job.BuildDockerElixir, "amd64"},
                  ["1.18.0", "27.0", "ubuntu", "noble-20250101"]},
                 {{Bob.Job.BuildDockerElixir, "arm64"},
                  ["1.18.0", "27.0", "ubuntu", "noble-20250101"]}
               ])
    end

    test "enqueues the erlang base first when it is missing" do
      assert {:ok, %BuildRequest{builds_count: 4}} = submit(@elixir_attrs)

      jobs = Repo.all(Job) |> Enum.map(& &1.module_key) |> Enum.sort()

      assert jobs ==
               Enum.sort([
                 {Bob.Job.BuildDockerErlang, "amd64"},
                 {Bob.Job.BuildDockerErlang, "arm64"}
               ])
    end

    test "rejects erlang versions elixir is never built for" do
      attrs = %{@elixir_attrs | elixir: "1.14.5", erlang: "26.0-rc1"}

      assert BuildRequests.submit(attrs) == {:error, :invalid_combo}
    end

    test "rejects a missing elixir version" do
      attrs = %{@elixir_attrs | elixir: nil}

      assert BuildRequests.submit(attrs) == {:error, :invalid_combo}
    end
  end

  describe "submit/1 rate limiting" do
    test "rejects requests over the hourly build limit" do
      {:ok, _request} =
        BuildRequests.create(Map.put(@erlang_attrs, :builds_count, 9))

      assert BuildRequests.submit(%{@erlang_attrs | erlang: "28.0"}) == {:error, :rate_limited}
      assert Repo.all(Job) == []
    end

    test "ignores requests older than an hour" do
      {:ok, request} = BuildRequests.create(Map.put(@erlang_attrs, :builds_count, 10))

      request
      |> Ecto.Changeset.change(inserted_at: DateTime.add(DateTime.utc_now(), -2, :hour))
      |> Repo.update!()

      assert {:ok, %BuildRequest{}} = submit(%{@erlang_attrs | erlang: "28.0"})
    end

    test "counts builds across requests within the hour" do
      {:ok, _request} = BuildRequests.create(Map.put(@erlang_attrs, :builds_count, 8))

      assert {:ok, %BuildRequest{builds_count: 2}} = submit(%{@erlang_attrs | erlang: "28.0"})
      assert BuildRequests.submit(%{@erlang_attrs | erlang: "28.1"}) == {:error, :rate_limited}
    end
  end

  describe "builds_count_for_user_since/2" do
    test "sums only the given user's requests" do
      {:ok, _} = BuildRequests.create(Map.put(@erlang_attrs, :builds_count, 2))
      {:ok, _} = BuildRequests.create(Map.put(@elixir_attrs, :builds_count, 4))

      {:ok, _} =
        BuildRequests.create(%{@erlang_attrs | username: "jose"} |> Map.put(:builds_count, 2))

      hour_ago = DateTime.add(DateTime.utc_now(), -1, :hour)

      assert BuildRequests.builds_count_for_user_since("eric", hour_ago) == 6
      assert BuildRequests.builds_count_for_user_since("jose", hour_ago) == 2
      assert BuildRequests.builds_count_for_user_since("nobody", hour_ago) == 0
    end
  end

  describe "pending/1" do
    test "returns a bounded oldest-first list of pending requests" do
      {:ok, oldest} = BuildRequests.create(Map.put(@erlang_attrs, :builds_count, 2))
      {:ok, completed} = BuildRequests.create(Map.put(@elixir_attrs, :builds_count, 4))

      {:ok, newest} =
        BuildRequests.create(
          %{@erlang_attrs | username: "jose", erlang: "28.0"}
          |> Map.put(:builds_count, 2)
        )

      oldest
      |> Ecto.Changeset.change(inserted_at: DateTime.add(DateTime.utc_now(), -3, :hour))
      |> Repo.update!()

      completed
      |> Ecto.Changeset.change(
        state: "completed",
        inserted_at: DateTime.add(DateTime.utc_now(), -2, :hour)
      )
      |> Repo.update!()

      newest
      |> Ecto.Changeset.change(inserted_at: DateTime.add(DateTime.utc_now(), -1, :hour))
      |> Repo.update!()

      assert [%BuildRequest{id: oldest_id}, %BuildRequest{id: newest_id}] =
               BuildRequests.pending(10)

      assert [oldest_id, newest_id] == [oldest.id, newest.id]

      assert [%BuildRequest{id: oldest_id}] = BuildRequests.pending(1)
      assert oldest_id == oldest.id
    end
  end

  defp submit(attrs) do
    BuildRequests.submit(attrs)
  end
end
