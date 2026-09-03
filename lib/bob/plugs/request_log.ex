defmodule Bob.Plug.RequestLog do
  @moduledoc """
  Logs one `http.request` event per request when the response is sent, with
  the method, path, status, duration and, once routed, the controller, action
  and format as fields. Client errors log as warnings and server errors as
  errors.
  """

  import Plug.Conn
  require Logger

  def init(opts), do: opts

  def call(conn, _opts) do
    start = System.monotonic_time()

    register_before_send(conn, fn conn ->
      duration_us =
        System.convert_time_unit(System.monotonic_time() - start, :native, :microsecond)

      Logger.log(level(conn.status), fields(conn, duration_us))
      conn
    end)
  end

  defp level(status) when status >= 500, do: :error
  defp level(status) when status >= 400, do: :warning
  defp level(_status), do: :info

  defp fields(conn, duration_us) do
    Enum.into(routed(conn.private), %{
      message: "HTTP request",
      event: "http.request",
      method: conn.method,
      path: conn.request_path,
      status: conn.status,
      duration_us: duration_us
    })
  end

  defp routed(%{phoenix_controller: controller, phoenix_action: action} = private) do
    [controller: inspect(controller), action: action] ++ format(private)
  end

  defp routed(_private), do: []

  defp format(%{phoenix_format: format}), do: [format: format]
  defp format(_private), do: []
end
