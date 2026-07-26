defmodule BobWeb.EndpointTest do
  use BobWeb.ConnCase

  test "emits the endpoint telemetry event PromEx builds its Phoenix metrics from", %{conn: conn} do
    ref = :telemetry_test.attach_event_handlers(self(), [[:phoenix, :endpoint, :stop]])

    conn
    |> put_req_header("accept", "application/json")
    |> get(~p"/api/artifacts")
    |> json_response(200)

    assert_received {[:phoenix, :endpoint, :stop], ^ref, %{duration: _}, %{conn: %Plug.Conn{}}}

    :telemetry.detach(ref)
  end
end
