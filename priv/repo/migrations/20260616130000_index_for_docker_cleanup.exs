defmodule Bob.Repo.Migrations.IndexForDockerCleanup do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # A previous attempt that was interrupted — a deadlock against a second
    # replica migrating at the same time, a cancelled statement — leaves the
    # index present but INVALID, and the planner ignores it. `IF NOT EXISTS`
    # matches on name alone, so it would skip that corpse and report success
    # while every cleanup query silently seq-scans millions of rows. Drop first
    # so a retry actually rebuilds. Dropping a valid index here costs one
    # rebuild on an already-migrated database and is never wrong.
    execute("DROP INDEX CONCURRENTLY IF EXISTS docker_tags_repo_built_at_index")

    # Cleanup scans a repo's tags by built_at and is scoped to a couple of
    # repos, so lead with repo. Reservations are matched by a hash anti-join
    # against build_requests, so no index is needed there.
    execute("""
    CREATE INDEX CONCURRENTLY IF NOT EXISTS docker_tags_repo_built_at_index
    ON docker_tags (repo, built_at)
    """)
  end

  def down do
    execute("DROP INDEX CONCURRENTLY IF EXISTS docker_tags_repo_built_at_index")
  end
end
