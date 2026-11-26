defmodule Bob.Repo.Migrations.AddPriorityAndReleaseOrderToJobs do
  use Ecto.Migration

  def change do
    alter table(:jobs) do
      add(:priority, :integer, default: 0, null: false)
      add(:release_order, {:array, :bigint}, default: [], null: false)
    end
  end
end
