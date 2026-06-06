defmodule Bob.Repo.Migrations.AllowNullBuildArtifactSha256 do
  use Ecto.Migration

  # OTP builds.txt entries written before the sha256 column was added carry only
  # `name ref date`, so backfilled rows for those builds have no checksum.
  def up do
    alter table(:build_artifacts) do
      modify :sha256, :string, null: true
    end
  end

  def down do
    alter table(:build_artifacts) do
      modify :sha256, :string, null: false
    end
  end
end
