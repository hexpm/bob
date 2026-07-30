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
    field(:state, :string, default: "pending")
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(build_request, attrs) do
    build_request
    |> cast(attrs, @fields)
    |> validate_required(@required)
    |> validate_inclusion(:kind, ~w(erlang elixir))
  end

  @doc "The Docker tag a request maps to."
  def target(%{kind: "erlang"} = request) do
    "#{request.erlang}-#{request.os}-#{request.os_version}"
  end

  def target(%{kind: "elixir"} = request) do
    "#{request.elixir}-erlang-#{request.erlang}-#{request.os}-#{request.os_version}"
  end
end
