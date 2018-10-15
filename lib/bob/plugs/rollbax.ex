defmodule Bob.Plug.Rollbax do
  defmacro __using__(_opts) do
    quote do
      defp handle_errors(conn, %{kind: kind, reason: reason, stack: stacktrace}) do
        if report?(kind, reason) do
          conn = maybe_fetch_params(conn)
          url = "#{conn.scheme}://#{conn.host}:#{conn.port}#{conn.request_path}"
          user_ip = conn.remote_ip |> :inet.ntoa() |> List.to_string()
          headers = Map.new(conn.req_headers)
          endpoint_url = conn.host <> conn.request_path

          conn_data = %{
            "request" => %{
              "url" => url,
              "user_ip" => user_ip,
              "headers" => headers,
              "params" => conn.params,
              "method" => conn.method
            },
            "server" => %{
              "host" => endpoint_url[:host],
              "root" => endpoint_url[:path]
            }
          }

          Rollbax.report(kind, reason, stacktrace, %{}, conn_data)
        end
      end

      defp report?(:error, exception), do: Plug.Exception.status(exception) == 500
      defp report?(_kind, _reason), do: true

      defp maybe_fetch_params(conn) do
        try do
          Plug.Conn.fetch_query_params(conn)
        rescue
          _ ->
            %{conn | params: "[UNFETCHED]"}
        end
      end
    end
  end
end
