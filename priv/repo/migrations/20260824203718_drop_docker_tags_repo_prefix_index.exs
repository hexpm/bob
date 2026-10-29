defmodule Bob.Repo.Migrations.DropDockerTagsRepoPrefixIndex do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    execute("DROP INDEX CONCURRENTLY IF EXISTS docker_tags_repo_prefix_index")
  end

  def down do
    execute(
      "CREATE INDEX CONCURRENTLY IF NOT EXISTS docker_tags_repo_prefix_index ON docker_tags (repo text_pattern_ops)"
    )
  end
end
