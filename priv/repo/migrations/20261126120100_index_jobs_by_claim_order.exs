defmodule Bob.Repo.Migrations.IndexJobsByClaimOrder do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # An interrupted build leaves an INVALID index that CREATE .. IF NOT EXISTS
    # would then skip by name, so drop first.
    execute("DROP INDEX CONCURRENTLY IF EXISTS jobs_claim_order_index")

    execute("""
    CREATE INDEX CONCURRENTLY IF NOT EXISTS jobs_claim_order_index
    ON jobs (module_key, state, priority DESC, version_order DESC, inserted_at, id)
    """)

    execute("DROP INDEX CONCURRENTLY IF EXISTS jobs_module_key_state_inserted_at_index")
  end

  def down do
    execute("""
    CREATE INDEX CONCURRENTLY IF NOT EXISTS jobs_module_key_state_inserted_at_index
    ON jobs (module_key, state, inserted_at)
    """)

    execute("DROP INDEX CONCURRENTLY IF EXISTS jobs_claim_order_index")
  end
end
