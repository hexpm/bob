defmodule Bob.Repo do
  use Ecto.Repo,
    otp_app: :bob,
    adapter: Ecto.Adapters.Postgres
end
