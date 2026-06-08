defmodule Bob.HTTP do
  require Logger

  @max_retry_times 10
  @error_sleep_time 100
  @rate_limit_sleep_time 10_000
  # Ceiling on a single backoff sleep. Without it the base-3 growth reaches ~11
  # minutes on the error path and ~18 hours on the rate-limit path by the last
  # retry, long enough to look like a hang.
  @max_sleep_time 30_000

  def request(method, url, headers, body, opts \\ []) do
    headers = put_basic_auth(headers, Keyword.get(opts, :basic_auth))

    method
    |> Finch.build(url, headers, body)
    |> Finch.request(Bob.Finch, request_opts(opts))
    |> read_response()
  end

  defp put_basic_auth(headers, nil), do: headers

  defp put_basic_auth(headers, {user, password}) do
    [{"authorization", "Basic " <> Base.encode64("#{user}:#{password}")} | headers]
  end

  defp request_opts(opts) do
    case Keyword.get(opts, :recv_timeout) do
      nil -> []
      timeout -> [receive_timeout: timeout]
    end
  end

  defp read_response({:ok, %Finch.Response{status: status, headers: headers, body: body}}) do
    {:ok, status, headers, body}
  end

  defp read_response({:error, reason}) do
    {:error, reason}
  end

  def retry(name, fun, opts \\ []) do
    retry(name, fun, 0, opts)
  end

  defp retry(name, fun, times, opts) do
    case fun.() do
      {:error, reason} ->
        Logger.warning("#{name} ERROR: #{inspect(reason)}")

        if times + 1 < @max_retry_times do
          Process.sleep(backoff(@error_sleep_time, times))
          retry(name, fun, times + 1, opts)
        else
          {:error, reason}
        end

      {:ok, 429, _headers, _body} = result ->
        # When the caller paces itself against the rate-limit window (the Docker
        # Hub pager), hand the 429 back silently so it can react to the headers;
        # the limiter logs the wait. Only blind-retry (and warn) otherwise.
        if Keyword.get(opts, :retry_rate_limit?, true) do
          Logger.warning("#{name} RATE LIMIT")

          if times + 1 < @max_retry_times do
            Process.sleep(backoff(@rate_limit_sleep_time, times))
            retry(name, fun, times + 1, opts)
          else
            result
          end
        else
          result
        end

      {:ok, status, _headers, _body} = result when status >= 500 ->
        Logger.warning("#{name} SERVER ERROR: #{status}")

        if times + 1 < @max_retry_times do
          Process.sleep(backoff(@error_sleep_time, times))
          retry(name, fun, times + 1, opts)
        else
          result
        end

      result ->
        result
    end
  end

  @doc false
  def backoff(base, times) do
    min(trunc(:math.pow(3, times) * base), @max_sleep_time)
  end
end
