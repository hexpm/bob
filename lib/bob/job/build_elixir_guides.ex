defmodule Bob.Job.BuildElixirGuides do
  require Logger

  def run([event, ref_name | _]) do
    directory = Bob.Directory.new()
    Logger.info("Using directory #{directory}")
    Bob.Script.run({:script, "elixir/elixir_guides.sh"}, [event, ref_name], directory)
  end

  def equal?(_, _), do: false

  def similar?(args, args), do: true
  def similar?(_, _), do: false
end
