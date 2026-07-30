defmodule Bob.Repo.Migrations.IndexForDockerCleanup do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # An interrupted build leaves an INVALID index that CREATE .. IF NOT EXISTS
    # would then skip by name, so drop first.
    execute("DROP INDEX CONCURRENTLY IF EXISTS docker_tags_repo_built_at_index")

    execute("""
    CREATE INDEX CONCURRENTLY IF NOT EXISTS docker_tags_repo_built_at_index
    ON docker_tags (repo, built_at)
    """)
  end

  def down do
    execute("DROP INDEX CONCURRENTLY IF EXISTS docker_tags_repo_built_at_index")
  end
end
