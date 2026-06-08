defmodule BobWeb.ConnCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      use BobWeb, :verified_routes

      import Plug.Conn
      import Phoenix.ConnTest
      import BobWeb.ConnCase

      alias Bob.Repo

      @endpoint BobWeb.Endpoint
    end
  end

  setup tags do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Bob.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)

    conn =
      Phoenix.ConnTest.build_conn()
      |> Map.put(:secret_key_base, BobWeb.Endpoint.config(:secret_key_base))

    {:ok, conn: conn}
  end
end
