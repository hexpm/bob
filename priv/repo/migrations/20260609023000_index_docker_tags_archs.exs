defmodule Bob.Repo.Migrations.IndexDockerTagsArchs do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    execute("CREATE INDEX CONCURRENTLY IF NOT EXISTS docker_tags_archs_gin_index ON docker_tags USING GIN (archs)")
  end

  def down do
    execute("DROP INDEX CONCURRENTLY IF EXISTS docker_tags_archs_gin_index")
  end
end
