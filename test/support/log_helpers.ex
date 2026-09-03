defmodule Bob.LogHelpers do
  @moduledoc """
  Captures what is logged at `:info` and above while `fun` runs as the JSON
  lines production writes, one decoded map per line.
  """

  @formatter {LoggerJSON.Formatters.GoogleCloud,
              metadata: {:from_application_env, {:bob, :log_metadata}}, reported_levels: []}

  def capture_json_log(fun) do
    handler = :"json_log_#{System.unique_integer([:positive])}"
    :ok = :logger.add_handler(handler, __MODULE__, %{config: %{pid: self()}})
    level = Logger.level()
    Logger.configure(level: :info)

    try do
      ExUnit.CaptureLog.capture_log(fun)
    after
      Logger.configure(level: level)
      :logger.remove_handler(handler)
    end

    collect([])
  end

  @doc false
  def log(event, %{config: %{pid: pid}}) do
    {module, opts} = @formatter
    send(pid, {__MODULE__, IO.iodata_to_binary(module.format(event, opts))})
  end

  defp collect(lines) do
    receive do
      {__MODULE__, line} -> collect([line | lines])
    after
      0 ->
        lines
        |> Enum.reverse()
        |> Enum.map(&(&1 |> String.trim_trailing("\n") |> JSON.decode!()))
    end
  end
end
