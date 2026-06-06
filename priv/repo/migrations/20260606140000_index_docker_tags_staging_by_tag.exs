defmodule Bob.Repo.Migrations.IndexDockerTagsStagingByTag do
  use Ecto.Migration

  # The swap's prune anti-join and the staged-count query look rows up by
  # (token, repo, tag); without the tag in the index those degrade to a scan per
  # row. This index also serves the (token, repo) prefix the staging writes use.
  def up do
    execute("DROP INDEX docker_tags_staging_token_repo_index")

    execute(
      "CREATE INDEX docker_tags_staging_token_repo_tag_index ON docker_tags_staging (token, repo, tag)"
    )
  end

  def down do
    execute("DROP INDEX docker_tags_staging_token_repo_tag_index")

    execute("CREATE INDEX docker_tags_staging_token_repo_index ON docker_tags_staging (token, repo)")
  end
end
