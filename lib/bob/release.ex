defmodule Bob.Release do
  @moduledoc """
  Migration entry point for production releases, which do not have Mix.

  Run on deploy with: `bin/bob eval "Bob.Release.migrate()"`.
  """
  @app :bob

  def migrate() do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  def backfill() do
    load_app()
    {:ok, _} = Application.ensure_all_started(:hackney)
    {:ok, _} = Application.ensure_all_started(:ex_aws)

    auth_dockerhub()

    Ecto.Migrator.with_repo(Bob.Repo, fn _repo ->
      Bob.Reconcile.backfill()
    end)
  end

  defp auth_dockerhub() do
    username = Application.get_env(@app, :dockerhub_username)
    password = Application.get_env(@app, :dockerhub_password)

    if username && password do
      Bob.DockerHub.auth(username, password)
    end
  end

  defp repos() do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app() do
    Application.load(@app)
  end
end
