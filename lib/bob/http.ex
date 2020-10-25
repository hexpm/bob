defmodule Bob.HTTP do
  require Logger

  @max_retry_times 10
  @base_sleep_time 100

  def retry(name, fun) do
    retry(name, fun, 0)
  end

  defp retry(name, fun, times) do
    case fun.() do
      {:error, reason} ->
        Logger.warn("#{name} API ERROR: #{inspect(reason)}")

        if times + 1 < @max_retry_times do
          sleep = trunc(:math.pow(3, times) * @base_sleep_time)
          :timer.sleep(sleep)
          retry(name, fun, times + 1)
        else
          {:error, reason}
        end

      result ->
        result
    end
  end
end
