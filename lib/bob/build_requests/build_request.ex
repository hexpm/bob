defmodule Bob.BuildRequests.BuildRequest do
  use Ecto.Schema

  import Ecto.Changeset

  @fields [:username, :kind, :elixir, :erlang, :os, :os_version, :builds_count]
  @required [:username, :kind, :erlang, :os, :os_version, :builds_count]

  schema "build_requests" do
    field(:username, :string)
    field(:kind, :string)
    field(:elixir, :string)
    field(:erlang, :string)
    field(:os, :string)
    field(:os_version, :string)
    field(:builds_count, :integer)
    field(:target, :string)
    field(:state, :string, default: "pending")
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(build_request, attrs) do
    build_request
    |> cast(attrs, @fields)
    |> validate_required(@required)
    |> validate_inclusion(:kind, ~w(erlang elixir))
    |> put_target()
  end

  @doc """
  The Docker tag name a request maps to. Stored on the row so the cleanup can
  match reservations with a plain equality join instead of rebuilding this in
  SQL, which meant two encodings of the same rule to keep in step.
  """
  def target(%{kind: "erlang"} = request) do
    "#{request.erlang}-#{request.os}-#{request.os_version}"
  end

  def target(%{kind: "elixir"} = request) do
    "#{request.elixir}-erlang-#{request.erlang}-#{request.os}-#{request.os_version}"
  end

  # Only derivable once the component fields validate, so an already-invalid
  # changeset is left alone rather than raising on a missing kind.
  defp put_target(%{valid?: true} = changeset) do
    put_change(changeset, :target, target(apply_changes(changeset)))
  end

  defp put_target(changeset), do: changeset
end
