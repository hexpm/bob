defmodule Bob.Repo.Migrations.AddPriorityToJobs do
  use Ecto.Migration

  def change do
    alter table(:jobs) do
      add(:priority, :integer, default: 0, null: false)
    end
  end
end
