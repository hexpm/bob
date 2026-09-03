defmodule Bob.LogHelpers do
  @doc """
  Captures what `fun` logs at `:info` and above as the JSON lines production
  writes, one decoded map per line.
  """
  def capture_json_log(fun) do
    level = Logger.level()
    Logger.configure(level: :info)

    formatter =
      {LoggerJSON.Formatters.GoogleCloud,
       metadata: Application.fetch_env!(:bob, :log_metadata), reported_levels: []}

    try do
      ExUnit.CaptureLog.capture_log([formatter: formatter], fun)
    after
      Logger.configure(level: level)
    end
    |> String.split("\n", trim: true)
    |> Enum.map(&JSON.decode!/1)
  end
end
