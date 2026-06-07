defmodule Bob.Repo.Migrations.CreateQueueTables do
  use Ecto.Migration

  def change do
    create table(:jobs) do
      add :module_key, :binary, null: false
      add :args, :binary, null: false
      add :args_digest, :binary, null: false
      add :state, :string, null: false
      add :inserted_at, :utc_datetime_usec, null: false
      add :updated_at, :utc_datetime_usec, null: false
      add :started_at, :utc_datetime_usec
      add :finished_at, :utc_datetime_usec
    end

    create index(:jobs, [:module_key, :state, :inserted_at])
    create index(:jobs, [:state, :finished_at])

    create unique_index(:jobs, [:module_key, :args_digest],
             where: "state IN ('queued', 'running')",
             name: :jobs_active_dedup_index
           )

    create table(:job_failures) do
      add :module_key, :binary, null: false
      add :args_digest, :binary, null: false
      add :count, :integer, null: false
      add :last_failed_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:job_failures, [:module_key, :args_digest])
  end
end
