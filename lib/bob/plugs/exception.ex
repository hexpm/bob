defmodule Bob.Plugs.Exception do
  @behaviour Plug.Wrapper

  import Plug.Conn

  def init(opts), do: opts

  def wrap(conn, _opts, fun) do
    try do
      fun.(conn)
    catch
      kind, error ->
        stacktrace = System.stacktrace
        status     = Plug.Exception.status(error)

        if status == 500, do: Bob.log_error(kind, error, stacktrace)

        send_resp(conn, status, "ERROR: #{status}")
    end
  end
end
