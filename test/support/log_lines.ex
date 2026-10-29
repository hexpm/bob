defmodule Bob.LogLines do
  @moduledoc """
  A `:logger` handler, attached for the test run, that sends every line a
  capturing process logs back to it as `{Bob.LogLines, level, fields}`. The
  fields are what production writes: the message map's keys, or `:message`
  for a plain message, and the process metadata that reaches the line.
  """

  @doc """
  Runs `fun` and returns the lines the calling process logged meanwhile, as
  `{level, fields}` with the fields production writes.
  """
  def capture_log_lines(fun) do
    Process.put(__MODULE__, true)

    try do
      fun.()
    after
      Process.delete(__MODULE__)
    end

    collect_log_lines([])
  end

  defp collect_log_lines(lines) do
    receive do
      {__MODULE__, level, fields} -> collect_log_lines([{level, fields} | lines])
    after
      0 -> Enum.reverse(lines)
    end
  end

  @doc false
  def log(%{level: level, msg: msg, meta: %{pid: pid} = meta}, _config) do
    if Process.get(__MODULE__), do: send(pid, {__MODULE__, level, fields(msg, meta)})
    :ok
  rescue
    _ -> :ok
  end

  def log(_event, _config), do: :ok

  defp fields({:report, report}, meta), do: Map.merge(metadata(meta), Map.new(report))

  defp fields({:string, chardata}, meta),
    do: Map.put(metadata(meta), :message, IO.chardata_to_string(chardata))

  defp fields({format, args}, meta),
    do: Map.put(metadata(meta), :message, format |> :io_lib.format(args) |> to_string())

  defp metadata(meta), do: Map.take(meta, Application.fetch_env!(:bob, :log_metadata))
end
