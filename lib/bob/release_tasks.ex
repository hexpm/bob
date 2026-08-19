defmodule Bob.ReleaseTasks do
  @moduledoc """
  Migration entry point for production releases, which do not have Mix.

  Run on deploy with: `bin/bob eval "Bob.ReleaseTasks.migrate()"`.
  """
  require Logger

  @app :bob
  @migration_lock_key 4_771_003
  @migration_lock_poll_interval 1_000

  def migrate() do
    load_app()

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn repo ->
          with_migration_lock(repo, fn -> Ecto.Migrator.run(repo, :up, all: true) end)
        end)
    end
  end

  def rollback(repo, version) do
    load_app()

    {:ok, _, _} =
      Ecto.Migrator.with_repo(repo, fn repo ->
        with_migration_lock(repo, fn -> Ecto.Migrator.run(repo, :down, to: version) end)
      end)
  end

  @doc false
  # Every pod runs migrate() at boot, so they race. Ecto's own migration lock
  # cannot serialize them here: it holds a transaction for the duration, and
  # CREATE INDEX CONCURRENTLY waits for concurrent transactions to finish, so
  # the two deadlock. A session level advisory lock on its own connection holds
  # no transaction once acquired, and the lock is released when that connection
  # ends, including when the pod dies mid-migration.
  #
  # Waiting for the lock must not hold a transaction either. A blocking
  # pg_advisory_lock() call is a running statement with a snapshot for as long
  # as it waits, and the holder's CREATE INDEX CONCURRENTLY waits for every
  # older snapshot to go away, so the two would deadlock through the app.
  # Polling pg_try_advisory_lock() leaves the connection idle between attempts.
  def with_migration_lock(repo, fun) do
    opts =
      Keyword.take(repo.config(), [
        :hostname,
        :port,
        :username,
        :password,
        :database,
        :socket_options,
        :ssl
      ])

    {:ok, conn} = Postgrex.start_link(opts)

    try do
      Logger.info("Waiting for migration lock")
      acquire_migration_lock(conn)
      Logger.info("Acquired migration lock")

      try do
        fun.()
      after
        Postgrex.query!(conn, "SELECT pg_advisory_unlock($1)", [@migration_lock_key])
      end
    after
      GenServer.stop(conn)
    end
  end

  @doc false
  def migration_lock_key(), do: @migration_lock_key

  defp acquire_migration_lock(conn) do
    %{rows: [[locked?]]} =
      Postgrex.query!(conn, "SELECT pg_try_advisory_lock($1)", [@migration_lock_key])

    unless locked? do
      Process.sleep(@migration_lock_poll_interval)
      acquire_migration_lock(conn)
    end
  end

  defp repos() do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app() do
    Application.load(@app)
  end
end
