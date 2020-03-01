defmodule Bob.Plug.Parser do
  alias Plug.Conn

  def parse(%Conn{} = conn, "application", "vnd.bob+erlang", _headers, opts) do
    conn
    |> Conn.read_body(opts)
    |> decode()
  end

  def parse(conn, _type, _subtype, _headers, _opts) do
    {:next, conn}
  end

  defp decode({:more, _, conn}) do
    {:error, :too_large, conn}
  end

  defp decode({:error, :timeout}) do
    raise Plug.TimeoutError
  end

  defp decode({:error, _}) do
    raise Plug.BadRequestError
  end

  defp decode({:ok, "", conn}) do
    {:ok, %{}, conn}
  end

  defp decode({:ok, body, conn}) do
    case Bob.Plug.ErlangFormat.decode(body) do
      {:ok, terms} when is_map(terms) ->
        {:ok, terms, conn}

      {:ok, terms} ->
        {:ok, %{"_json" => terms}, conn}

      {:error, reason} ->
        raise Plug.BadRequestError, message: reason
    end
  end
end
