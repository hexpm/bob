defmodule Bob.Plugs.Exception do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, [fun: fun]) do
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
