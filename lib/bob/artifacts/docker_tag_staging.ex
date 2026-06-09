defmodule Bob.Artifacts.DockerTagStaging do
  use Ecto.Schema

  @primary_key false
  schema "docker_tags_staging" do
    field(:token, :string)
    field(:repo, :string)
    field(:tag, :string)
    field(:archs, {:array, :string})
    field(:search, :map, default: %{})
    field(:built_at, :utc_datetime_usec)
    field(:inserted_at, :naive_datetime_usec)
  end
end
