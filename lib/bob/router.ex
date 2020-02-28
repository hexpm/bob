defmodule Bob.Router do
  # use Plug.Router
  use Plug.Builder
  use Bob.Plug.Rollbax

  # import Plug.Conn

  def call(conn, opts) do
    Bob.Plug.Exception.call(conn, fun: &super(&1, opts))
  end

  plug(Bob.Plug.Forwarded)
  plug(Bob.Plug.Status)
  # TODO: SSL?
  # plug(:match)
  # plug(:dispatch)
end
