defmodule Bob.Repo.Migrations.AddRequeuesToJobs do
  use Ecto.Migration

  def change do
    alter table(:jobs) do
      add(:requeues, :integer, default: 0, null: false)
    end
  end
end
