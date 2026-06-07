defmodule Bob.Repo.Migrations.CreateBuildArtifacts do
  use Ecto.Migration

  def change do
    create table(:build_artifacts) do
      add :kind, :string, null: false
      add :arch, :string, null: false
      add :os, :string, null: false
      add :name, :string, null: false
      add :ref, :string, null: false
      add :sha256, :string, null: false
      add :built_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:build_artifacts, [:kind, :arch, :os, :name])
  end
end
