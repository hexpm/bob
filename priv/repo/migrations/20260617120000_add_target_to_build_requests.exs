defmodule Bob.Repo.Migrations.AddTargetToBuildRequests do
  use Ecto.Migration

  # The Docker tag a request maps to. Cleanup matches reservations by equality
  # on this rather than rebuilding the tag name from the component columns in
  # SQL, which needed a CASE the Elixir side had to be kept in step with.
  def up do
    alter table(:build_requests) do
      add(:target, :string)
    end

    execute("""
    UPDATE build_requests
    SET target =
      CASE kind
        WHEN 'erlang' THEN erlang || '-' || os || '-' || os_version
        ELSE elixir || '-erlang-' || erlang || '-' || os || '-' || os_version
      END
    """)

    execute("ALTER TABLE build_requests ALTER COLUMN target SET NOT NULL")

    create(index(:build_requests, [:target]))
  end

  def down do
    alter table(:build_requests) do
      remove(:target)
    end
  end
end
