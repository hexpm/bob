defmodule Bob.Job.BuildElixirGuides do
  require Logger

  def run(ref) do
    directory = Bob.Directory.new()
    Logger.info("Using directory #{directory}")
    Bob.Script.run({:script, "elixir/elixir_guides.sh"}, [ref], directory)
  end

  def priority(), do: 2
  def weight(), do: 2
end
