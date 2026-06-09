defmodule Bob.Repo.Migrations.IndexDockerTagsByBuiltAt do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    execute("""
    CREATE INDEX CONCURRENTLY IF NOT EXISTS docker_tags_built_at_id_desc_index
    ON docker_tags (built_at DESC, id DESC)
    """)
  end

  def down do
    execute("DROP INDEX CONCURRENTLY IF EXISTS docker_tags_built_at_id_desc_index")
  end
end
