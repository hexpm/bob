defmodule Bob.Repo.Migrations.CreateDockerTagsStaging do
  use Ecto.Migration

  # UNLOGGED: the table is a transient scratch space for reconcile. Skipping WAL
  # makes the bulk page inserts cheaper, and crash-truncation gives us free
  # cleanup of rows orphaned by an unclean shutdown.
  def up do
    execute("""
    CREATE UNLOGGED TABLE docker_tags_staging (
      token text NOT NULL,
      repo text NOT NULL,
      tag text NOT NULL,
      archs text[] NOT NULL,
      inserted_at timestamp NOT NULL DEFAULT (now() AT TIME ZONE 'utc')
    )
    """)

    execute("CREATE INDEX docker_tags_staging_token_repo_index ON docker_tags_staging (token, repo)")

    execute("CREATE INDEX docker_tags_staging_inserted_at_index ON docker_tags_staging (inserted_at)")
  end

  def down do
    execute("DROP TABLE docker_tags_staging")
  end
end
