defmodule Bob.Repo.Migrations.IndexForDockerCleanup do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # Cleanup scans a repo's tags by built_at, and is scoped to the four
    # per-arch repos, so lead with repo. Reservations are matched by a hash
    # anti-join against the small build_requests table, so no index is needed
    # there.
    execute("""
    CREATE INDEX CONCURRENTLY IF NOT EXISTS docker_tags_repo_built_at_index
    ON docker_tags (repo, built_at)
    """)
  end

  def down do
    execute("DROP INDEX CONCURRENTLY IF EXISTS docker_tags_repo_built_at_index")
  end
end
