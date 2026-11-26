defmodule Bob.Repo.Migrations.AddPriorityAndVersionOrderToJobs do
  use Ecto.Migration

  def change do
    alter table(:jobs) do
      add(:priority, :integer, default: 0, null: false)
      add(:version_order, {:array, :integer}, default: [], null: false)
    end
  end
end
