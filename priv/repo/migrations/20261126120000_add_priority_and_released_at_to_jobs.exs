defmodule Bob.Repo.Migrations.AddPriorityAndReleasedAtToJobs do
  use Ecto.Migration

  def change do
    alter table(:jobs) do
      add(:priority, :integer, default: 0, null: false)
      add(:released_at, :utc_datetime)
    end
  end
end
