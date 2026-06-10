defmodule Bob.Repo.Migrations.CreateScheduleLedger do
  use Ecto.Migration

  def change do
    create table(:schedule_ledger) do
      add :module_key, :binary, null: false
      add :args_digest, :binary, null: false
      add :last_run_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:schedule_ledger, [:module_key, :args_digest])
  end
end
