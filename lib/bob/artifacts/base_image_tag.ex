defmodule Bob.Artifacts.BaseImageTag do
  use Ecto.Schema

  schema "base_image_tags" do
    field(:repo, :string)
    field(:tag, :string)
    timestamps(type: :utc_datetime_usec)
  end
end
