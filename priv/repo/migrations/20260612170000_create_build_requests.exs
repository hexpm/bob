defmodule Bob.Repo.Migrations.CreateBuildRequests do
  use Ecto.Migration

  def change do
    create table(:build_requests) do
      add :username, :string, null: false
      add :kind, :string, null: false
      add :elixir, :string
      add :erlang, :string, null: false
      add :os, :string, null: false
      add :os_version, :string, null: false
      add :builds_count, :integer, null: false
      add :state, :string, null: false, default: "pending"
      timestamps(type: :utc_datetime_usec)
    end

    create index(:build_requests, [:username, :inserted_at])
    create index(:build_requests, [:state], where: "state = 'pending'")
  end
end
