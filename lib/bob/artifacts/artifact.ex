defmodule Bob.Artifacts.Artifact do
  use Ecto.Schema

  import Ecto.Changeset

  @fields [:kind, :arch, :os, :name, :ref, :sha256, :built_at]

  schema "build_artifacts" do
    field(:kind, :string)
    field(:arch, :string)
    field(:os, :string)
    field(:name, :string)
    field(:ref, :string)
    field(:sha256, :string)
    field(:built_at, :utc_datetime_usec)
  end

  def changeset(artifact, attrs) do
    artifact
    |> cast(attrs, @fields)
    |> validate_required(@fields)
  end
end
