defmodule Bob.Queue.Job do
  use Ecto.Schema

  schema "jobs" do
    field(:module_key, Bob.Queue.Term)
    field(:args, Bob.Queue.Term)
    field(:args_digest, :binary)
    field(:state, :string)
    field(:inserted_at, :utc_datetime_usec)
    field(:updated_at, :utc_datetime_usec)
    field(:started_at, :utc_datetime_usec)
    field(:finished_at, :utc_datetime_usec)
  end
end
