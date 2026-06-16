defmodule Bob.Repo.Migrations.IndexForDockerCleanup do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # Per-arch cleanup scans a repo's tags by built_at; manifest cleanup by
    # last_pulled. Both are scoped to a handful of repos, so lead with repo.
    # Reservations are matched by a hash anti-join against the small
    # build_requests table, so no index is needed there.
    execute("""
    CREATE INDEX CONCURRENTLY IF NOT EXISTS docker_tags_repo_built_at_index
    ON docker_tags (repo, built_at)
    """)

    execute("""
    CREATE INDEX CONCURRENTLY IF NOT EXISTS docker_tags_repo_last_pulled_index
    ON docker_tags (repo, last_pulled)
    """)
  end

  def down do
    execute("DROP INDEX CONCURRENTLY IF EXISTS docker_tags_repo_built_at_index")
    execute("DROP INDEX CONCURRENTLY IF EXISTS docker_tags_repo_last_pulled_index")
  end
end
