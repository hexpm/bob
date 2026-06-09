defmodule Bob.Repo.Migrations.AddDockerTagSearchMetadata do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true
  @version_regex "^[0-9]+(\\.[0-9]+)*(-[0-9A-Za-z][0-9A-Za-z.-]*)?$"

  def up do
    execute("ALTER TABLE docker_tags ADD COLUMN IF NOT EXISTS search jsonb NOT NULL DEFAULT '{}'::jsonb")

    execute(
      "ALTER TABLE docker_tags_staging ADD COLUMN IF NOT EXISTS search jsonb NOT NULL DEFAULT '{}'::jsonb"
    )

    execute("""
    UPDATE docker_tags d
    SET search = jsonb_build_object(
      'erlang_version', (parsed.m)[1],
      'os', (parsed.m)[2],
      'os_version', (parsed.m)[3]
    )
    FROM (
      SELECT id, regexp_match(tag, '^(.+)-(alpine|ubuntu|debian)-(.+)$') AS m
      FROM docker_tags
      WHERE repo IN ('hexpm/erlang', 'hexpm/erlang-amd64', 'hexpm/erlang-arm64')
    ) AS parsed
    WHERE d.id = parsed.id
      AND parsed.m IS NOT NULL
      AND (parsed.m)[1] ~ '#{@version_regex}'
    """)

    execute("""
    UPDATE docker_tags d
    SET search = jsonb_build_object(
      'elixir_version', (parsed.m)[1],
      'erlang_version', (parsed.m)[2],
      'os', (parsed.m)[3],
      'os_version', (parsed.m)[4]
    )
    FROM (
      SELECT id, regexp_match(tag, '^(.+)-erlang-(.+)-(alpine|ubuntu|debian)-(.+)$') AS m
      FROM docker_tags
      WHERE repo IN ('hexpm/elixir', 'hexpm/elixir-amd64', 'hexpm/elixir-arm64')
    ) AS parsed
    WHERE d.id = parsed.id
      AND parsed.m IS NOT NULL
      AND (parsed.m)[1] ~ '#{@version_regex}'
      AND (parsed.m)[2] ~ '#{@version_regex}'
    """)

    execute(
      "CREATE INDEX CONCURRENTLY IF NOT EXISTS docker_tags_repo_prefix_index ON docker_tags (repo text_pattern_ops)"
    )

    execute(
      "CREATE INDEX CONCURRENTLY IF NOT EXISTS docker_tags_tag_prefix_index ON docker_tags (tag text_pattern_ops)"
    )

    execute("""
    CREATE INDEX CONCURRENTLY IF NOT EXISTS docker_tags_elixir_version_prefix_index
    ON docker_tags ((search->>'elixir_version') text_pattern_ops)
    """)

    execute("""
    CREATE INDEX CONCURRENTLY IF NOT EXISTS docker_tags_erlang_version_prefix_index
    ON docker_tags ((search->>'erlang_version') text_pattern_ops)
    """)

    execute("""
    CREATE INDEX CONCURRENTLY IF NOT EXISTS docker_tags_os_prefix_index
    ON docker_tags ((search->>'os') text_pattern_ops)
    """)

    execute("""
    CREATE INDEX CONCURRENTLY IF NOT EXISTS docker_tags_os_version_prefix_index
    ON docker_tags ((search->>'os_version') text_pattern_ops)
    """)
  end

  def down do
    execute("DROP INDEX CONCURRENTLY IF EXISTS docker_tags_os_version_prefix_index")
    execute("DROP INDEX CONCURRENTLY IF EXISTS docker_tags_os_prefix_index")
    execute("DROP INDEX CONCURRENTLY IF EXISTS docker_tags_erlang_version_prefix_index")
    execute("DROP INDEX CONCURRENTLY IF EXISTS docker_tags_elixir_version_prefix_index")
    execute("DROP INDEX CONCURRENTLY IF EXISTS docker_tags_tag_prefix_index")
    execute("DROP INDEX CONCURRENTLY IF EXISTS docker_tags_repo_prefix_index")
    execute("ALTER TABLE docker_tags_staging DROP COLUMN IF EXISTS search")
    execute("ALTER TABLE docker_tags DROP COLUMN IF EXISTS search")
  end
end
