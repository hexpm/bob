defmodule BobWeb.RequestLogTest do
  use BobWeb.ConnCase

  test "logs one line per request with its fields", %{conn: conn} do
    assert [line] =
             capture_json_log(fn ->
               conn
               |> put_req_header("accept", "application/json")
               |> get(~p"/api/artifacts")
               |> json_response(200)
             end)

    assert %{
             "severity" => "INFO",
             "message" => "HTTP request",
             "event" => "http.request",
             "method" => "GET",
             "path" => "/api/artifacts",
             "status" => 200,
             "duration_us" => duration,
             "controller" => "BobWeb.PublicApiController",
             "action" => "artifacts",
             "format" => "json",
             "request_id" => request_id
           } = line

    assert is_integer(duration)
    assert is_binary(request_id)
  end

  test "logs a refused request as a warning", %{conn: conn} do
    assert [line] =
             capture_json_log(fn ->
               assert conn |> post(~p"/api/queue/add") |> response(401)
             end)

    assert %{
             "severity" => "WARNING",
             "event" => "http.request",
             "method" => "POST",
             "path" => "/api/queue/add",
             "status" => 401
           } = line

    refute Map.has_key?(line, "controller")
  end
end
