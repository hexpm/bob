defmodule Bob.Artifacts.DockerTag do
  use Ecto.Schema

  schema "docker_tags" do
    field(:repo, :string)
    field(:tag, :string)
    field(:archs, {:array, :string})
    field(:search, :map, default: %{})
    field(:built_at, :utc_datetime_usec)
    timestamps(type: :utc_datetime_usec)
  end
end
