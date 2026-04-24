defmodule Bob.FakeHttpClient do
  @behaviour ExAws.Request.HttpClient

  @impl true
  def request(method, url, _body, _headers, _http_opts) do
    case :persistent_term.get({__MODULE__, {method, url}}, :not_found) do
      :not_found -> {:ok, %{status_code: 404, headers: [], body: not_found_body(url)}}
      response -> {:ok, response}
    end
  end

  def stub(method, url, status_code, body) do
    :persistent_term.put(
      {__MODULE__, {method, url}},
      %{status_code: status_code, headers: [], body: body}
    )
  end

  def reset() do
    for {{__MODULE__, _key} = key, _value} <- :persistent_term.get() do
      :persistent_term.erase(key)
    end
  end

  defp not_found_body(url) do
    key = URI.parse(url).path |> String.trim_leading("/")

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <Error><Code>NoSuchKey</Code><Message>The specified key does not exist.</Message><Key>#{key}</Key></Error>
    """
  end
end
