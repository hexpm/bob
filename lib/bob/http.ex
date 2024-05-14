defmodule Bob.HTTP do
  require Logger

  @max_retry_times 10
  @error_sleep_time 100
  @rate_limit_sleep_time 10_000

  def retry(name, fun) do
    retry(name, fun, 0)
  end

  defp retry(name, fun, times) do
    case fun.() do
      {:error, reason} ->
        Logger.warning("#{name} ERROR: #{inspect(reason)}")

        if times + 1 < @max_retry_times do
          sleep = trunc(:math.pow(3, times) * @error_sleep_time)
          Process.sleep(sleep)
          retry(name, fun, times + 1)
        else
          {:error, reason}
        end

      {:ok, 429, _headers, _body} = result ->
        Logger.warning("#{name} RATE LIMIT")

        if times + 1 < @max_retry_times do
          sleep = trunc(:math.pow(3, times) * @rate_limit_sleep_time)
          Process.sleep(sleep)
          retry(name, fun, times + 1)
        else
          result
        end

      result ->
        result
    end
  end
end
