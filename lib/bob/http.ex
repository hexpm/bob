defmodule Bob.HTTP do
  require Logger

  @max_retry_times 10
  @error_sleep_time 100
  @rate_limit_sleep_time 10_000

  def retry(name, fun, opts \\ []) do
    retry(name, fun, 0, opts)
  end

  defp retry(name, fun, times, opts) do
    case fun.() do
      {:error, reason} ->
        Logger.warning("#{name} ERROR: #{inspect(reason)}")

        if times + 1 < @max_retry_times do
          sleep = trunc(:math.pow(3, times) * @error_sleep_time)
          Process.sleep(sleep)
          retry(name, fun, times + 1, opts)
        else
          {:error, reason}
        end

      {:ok, 429, _headers, _body} = result ->
        Logger.warning("#{name} RATE LIMIT")

        # When the caller paces itself against the rate-limit window (the Docker
        # Hub pager), hand the 429 back so it can react to the headers instead of
        # blind-sleeping here.
        if Keyword.get(opts, :retry_rate_limit?, true) and times + 1 < @max_retry_times do
          sleep = trunc(:math.pow(3, times) * @rate_limit_sleep_time)
          Process.sleep(sleep)
          retry(name, fun, times + 1, opts)
        else
          result
        end

      result ->
        result
    end
  end
end
