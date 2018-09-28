defmodule Bob.Job.BuildElixir do
  require Logger

  def run([event, ref]) do
    directory = Bob.Directory.new()
    Logger.info("Using directory #{directory}")
    Bob.Script.run({:script, "build_elixir.sh"}, [event, ref], directory)
  end

  def equal?(_, _), do: false

  def similar?(args, args), do: true
  def similar?(_, _), do: false
end
