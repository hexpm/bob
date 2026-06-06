defmodule Bob.ReleaseTasks do
  @moduledoc """
  Migration entry point for production releases, which do not have Mix.

  Run on deploy with: `bin/bob eval "Bob.ReleaseTasks.migrate()"`.
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

  defp repos() do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app() do
    Application.load(@app)
  end
end
