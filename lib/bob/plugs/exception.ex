defmodule Bob.Plug.Exception do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, fun: fun) do
    try do
      fun.(conn)
    catch
      kind, error ->
        status = Plug.Exception.status(error)

        if status == 500, do: Bob.log_error(kind, error, __STACKTRACE__)

        send_resp(conn, status, "ERROR: #{status}")
    end
  end
end
