defmodule Bob.Repo.Migrations.CreateDockerTagTables do
  use Ecto.Migration

  def change do
    create table(:docker_tags) do
      add :repo, :string, null: false
      add :tag, :string, null: false
      add :archs, {:array, :string}, null: false
      add :built_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:docker_tags, [:repo, :tag])

    create table(:base_image_tags) do
      add :repo, :string, null: false
      add :tag, :string, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:base_image_tags, [:repo, :tag])
  end
end
