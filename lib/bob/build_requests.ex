defmodule Bob.BuildRequests do
  import Ecto.Query

  require Logger

  alias Bob.BuildRequests.BuildRequest
  alias Bob.Repo

  @hourly_build_limit 10

  def hourly_build_limit(), do: @hourly_build_limit

  def submit(attrs) do
    request = struct!(BuildRequest, attrs)

    with :ok <- validate_combo(request) do
      case Bob.Job.DockerChecker.request_jobs(request) do
        [] ->
          reserve(request, attrs)
          {:ok, :already_built}

        jobs ->
          submit_jobs(request, attrs, jobs)
      end
    end
  end

  # An already-built image still records a request, so a manual request doubles as
  # a permanent reservation that exempts the image from cleanup. No build runs, so
  # it costs nothing against the hourly limit; an existing reservation for the same
  # target is left in place rather than duplicated. The check-then-insert is
  # serialized on the target — reservations dedupe across users, so a per-user
  # lock would not keep two users' concurrent submits from both inserting.
  defp reserve(request, attrs) do
    {:ok, :ok} =
      Repo.transaction(fn ->
        lock_target(request)

        unless reserved?(request) do
          {:ok, created} = create(Map.put(attrs, :builds_count, 0))
          created = complete(created)

          Logger.info(
            "BUILD RESERVATION by #{created.username}: #{created.kind} #{request_target(created)}"
          )
        end

        :ok
      end)

    :ok
  end

  defp lock_target(request) do
    Repo.query!("SELECT pg_advisory_xact_lock(hashtext($1))", [
      "#{request.kind}:#{request_target(request)}"
    ])
  end

  defp reserved?(request) do
    query =
      from(request_row in BuildRequest,
        where:
          request_row.state in ["pending", "completed"] and request_row.kind == ^request.kind and
            request_row.erlang == ^request.erlang and request_row.os == ^request.os and
            request_row.os_version == ^request.os_version
      )

    query =
      if request.kind == "elixir" do
        from(request_row in query, where: request_row.elixir == ^request.elixir)
      else
        query
      end

    Repo.exists?(query)
  end

  defp submit_jobs(request, attrs, jobs) do
    builds_count = builds_count(request.kind, jobs)

    # Serialize a user's concurrent submits (e.g. two tabs) with a per-user
    # advisory lock so the limit check and insert can't interleave and both
    # slip past the cap.
    result =
      Repo.transaction(fn ->
        lock_user(request.username)

        if over_limit?(request.username, builds_count) do
          Repo.rollback(:rate_limited)
        else
          {:ok, created} = create(Map.put(attrs, :builds_count, builds_count))
          created
        end
      end)

    case result do
      {:ok, created} ->
        # Enqueue outside the lock; if it fails the request stays pending and
        # the checker's reconciliation enqueues the jobs on its next cycle.
        Bob.Queue.add_many(jobs)

        Logger.info(
          "BUILD REQUEST by #{created.username}: #{created.kind} #{request_target(created)}"
        )

        {:ok, created}

      {:error, :rate_limited} ->
        {:error, :rate_limited}
    end
  end

  defp lock_user(username) do
    Repo.query!("SELECT pg_advisory_xact_lock(hashtext($1))", [username])
  end

  defp validate_combo(%{kind: "erlang"} = request) do
    if Bob.Job.DockerChecker.valid_erlang_build?(request.erlang, request.os, request.os_version) do
      :ok
    else
      {:error, :invalid_combo}
    end
  end

  defp validate_combo(%{kind: "elixir"} = request) do
    otp_major = request.erlang |> String.split(".") |> hd()

    if request.elixir != nil and
         Bob.Job.DockerChecker.valid_elixir_build?(
           request.elixir,
           otp_major,
           request.erlang,
           request.os,
           request.os_version
         ) do
      :ok
    else
      {:error, :invalid_combo}
    end
  end

  # Only image builds count against the hourly limit; manifest assembly is
  # cheap. An erlang job under an elixir request implies a follow-up elixir
  # build on the same arch, so it counts as two.
  defp builds_count("erlang", jobs) do
    Enum.count(jobs, &match?({{Bob.Job.BuildDockerErlang, _arch}, _args}, &1))
  end

  defp builds_count("elixir", jobs) do
    Enum.reduce(jobs, 0, fn
      {{Bob.Job.BuildDockerErlang, _arch}, _args}, acc -> acc + 2
      {{Bob.Job.BuildDockerElixir, _arch}, _args}, acc -> acc + 1
      _other, acc -> acc
    end)
  end

  defp over_limit?(username, builds_count) do
    hour_ago = DateTime.add(DateTime.utc_now(), -1, :hour)
    builds_count_for_user_since(username, hour_ago) + builds_count > @hourly_build_limit
  end

  @doc """
  The Docker tag name a request maps to. The reservation predicate in
  `Bob.Artifacts` rebuilds this same mapping in SQL, and a test asserts the two
  encodings agree — update both together.
  """
  def request_target(%{kind: "erlang"} = request) do
    "#{request.erlang}-#{request.os}-#{request.os_version}"
  end

  def request_target(%{kind: "elixir"} = request) do
    "#{request.elixir}-erlang-#{request.erlang}-#{request.os}-#{request.os_version}"
  end

  def create(attrs) do
    %BuildRequest{}
    |> BuildRequest.changeset(attrs)
    |> Repo.insert()
  end

  def pending() do
    Repo.all(pending_query())
  end

  def pending(limit) when is_integer(limit) and limit > 0 do
    Repo.all(
      from(request in pending_query(),
        limit: ^limit
      )
    )
  end

  def complete(request), do: set_state(request, "completed")

  def expire(request), do: set_state(request, "expired")

  def builds_count_for_user_since(username, since) do
    Repo.one(
      from(request in BuildRequest,
        where: request.username == ^username and request.inserted_at >= ^since,
        select: coalesce(sum(request.builds_count), 0)
      )
    )
  end

  def recent(limit, offset) do
    Repo.all(
      from(request in BuildRequest,
        order_by: [desc: request.inserted_at],
        limit: ^limit,
        offset: ^offset
      )
    )
  end

  def count() do
    Repo.aggregate(BuildRequest, :count)
  end

  @doc """
  Deletes expired requests older than `older_than_seconds`. Completed requests
  are permanent reservations and pending requests are still in flight, so only
  expired dead-ends (an os_version that rotated out, or a request past its TTL)
  are reclaimed.
  """
  def prune(older_than_seconds) do
    cutoff = DateTime.add(DateTime.utc_now(), -older_than_seconds, :second)

    {count, _} =
      Repo.delete_all(
        from(request in BuildRequest,
          where: request.state == "expired" and request.inserted_at < ^cutoff
        )
      )

    count
  end

  defp pending_query() do
    from(request in BuildRequest,
      where: request.state == "pending",
      order_by: [asc: request.inserted_at]
    )
  end

  defp set_state(request, state) do
    request
    |> Ecto.Changeset.change(state: state)
    |> Repo.update!()
  end
end
