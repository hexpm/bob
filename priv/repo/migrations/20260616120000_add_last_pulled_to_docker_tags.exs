defmodule Bob.Repo.Migrations.AddLastPulledToDockerTags do
  use Ecto.Migration

  def change do
    alter table(:docker_tags) do
      add(:last_pulled, :utc_datetime_usec)
    end

    alter table(:docker_tags_staging) do
      add(:last_pulled, :utc_datetime_usec)
    end
  end
end
