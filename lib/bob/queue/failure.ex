defmodule Bob.Queue.Failure do
  use Ecto.Schema

  schema "job_failures" do
    field(:module_key, Bob.Queue.Term)
    field(:args_digest, :binary)
    field(:count, :integer)
    field(:last_failed_at, :utc_datetime_usec)
    timestamps(type: :utc_datetime_usec)
  end
end
