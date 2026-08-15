defmodule Bob.Repo.Migrations.IndexDockerTagsByVersion do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    execute("""
    CREATE OR REPLACE FUNCTION docker_tag_natural_sort_key(value text)
    RETURNS bytea
    LANGUAGE SQL
    IMMUTABLE
    STRICT
    PARALLEL SAFE
    AS $$
      SELECT string_agg(
        CASE
          WHEN token ~ '^[0-9]+$' THEN
            decode('02', 'hex') ||
            int4send(length(normalized)) ||
            normalized::bytea ||
            decode('00', 'hex')
          ELSE
            decode('01', 'hex') ||
            lower(token)::bytea ||
            decode('00', 'hex')
        END,
        ''::bytea
        ORDER BY position
      )
      FROM (
        SELECT
          matches[1] AS token,
          position,
          coalesce(nullif(ltrim(matches[1], '0'), ''), '0') AS normalized
        FROM regexp_matches(value, '([0-9]+|[^0-9]+)', 'g')
          WITH ORDINALITY AS parts(matches, position)
      ) AS tokens
    $$
    """)

    execute("""
    CREATE INDEX CONCURRENTLY IF NOT EXISTS docker_tags_elixir_version_desc_index
    ON docker_tags (
      (docker_tag_natural_sort_key(split_part(search->>'elixir_version', '-', 1))) DESC NULLS LAST,
      ((strpos(search->>'elixir_version', '-') = 0)) DESC NULLS LAST,
      (docker_tag_natural_sort_key(search->>'elixir_version')) DESC NULLS LAST
    )
    """)

    execute("""
    CREATE INDEX CONCURRENTLY IF NOT EXISTS docker_tags_erlang_version_desc_index
    ON docker_tags (
      (docker_tag_natural_sort_key(split_part(search->>'erlang_version', '-', 1))) DESC NULLS LAST,
      ((strpos(search->>'erlang_version', '-') = 0)) DESC NULLS LAST,
      (docker_tag_natural_sort_key(search->>'erlang_version')) DESC NULLS LAST
    )
    """)

    execute("""
    CREATE INDEX CONCURRENTLY IF NOT EXISTS docker_tags_os_version_desc_index
    ON docker_tags (
      (docker_tag_natural_sort_key(search->>'os_version')) DESC NULLS LAST
    )
    """)

    execute("""
    CREATE INDEX CONCURRENTLY IF NOT EXISTS docker_tags_os_desc_index
    ON docker_tags (
      (search->>'os') DESC NULLS LAST,
      built_at DESC,
      id DESC
    )
    """)

    execute("""
    DO $$
    DECLARE
      invalid_indexes text;
    BEGIN
      SELECT string_agg(index_class.relname, ', ' ORDER BY index_class.relname)
      INTO invalid_indexes
      FROM pg_index AS index_metadata
      JOIN pg_class AS index_class ON index_class.oid = index_metadata.indexrelid
      JOIN pg_namespace AS namespace ON namespace.oid = index_class.relnamespace
      WHERE namespace.nspname = current_schema()
        AND index_class.relname IN (
          'docker_tags_elixir_version_desc_index',
          'docker_tags_erlang_version_desc_index',
          'docker_tags_os_version_desc_index',
          'docker_tags_os_desc_index'
        )
        AND NOT index_metadata.indisvalid;

      IF invalid_indexes IS NOT NULL THEN
        RAISE EXCEPTION 'invalid Docker tag sort indexes: %', invalid_indexes;
      END IF;
    END
    $$
    """)
  end

  def down do
    execute("DROP INDEX CONCURRENTLY IF EXISTS docker_tags_os_desc_index")
    execute("DROP INDEX CONCURRENTLY IF EXISTS docker_tags_os_version_desc_index")
    execute("DROP INDEX CONCURRENTLY IF EXISTS docker_tags_erlang_version_desc_index")
    execute("DROP INDEX CONCURRENTLY IF EXISTS docker_tags_elixir_version_desc_index")
    execute("DROP FUNCTION IF EXISTS docker_tag_natural_sort_key(text)")
  end
end
