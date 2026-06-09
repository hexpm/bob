defmodule Bob.Repo.Migrations.AddBuiltAtToDockerTagsStaging do
  use Ecto.Migration

  def up do
    execute("ALTER TABLE docker_tags_staging ADD COLUMN built_at timestamp")
    execute("UPDATE docker_tags_staging SET built_at = inserted_at")
    execute("ALTER TABLE docker_tags_staging ALTER COLUMN built_at SET NOT NULL")
  end

  def down do
    execute("ALTER TABLE docker_tags_staging DROP COLUMN built_at")
  end
end
