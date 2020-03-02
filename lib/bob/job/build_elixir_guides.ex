defmodule Bob.Job.BuildElixirGuides do
  require Logger

  def run([ref]) do
    directory = Bob.Directory.new()
    Logger.info("Using directory #{directory}")
    Bob.Script.run({:script, "elixir/elixir_guides.sh"}, [ref], directory)
  end

  def equal?(args, args), do: true
  def equal?(_, _), do: false

  def similar?(args, args), do: true
  def similar?(_, _), do: false
end
