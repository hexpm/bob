defmodule Bob.Job.BuildElixirGuides do
  require Logger

  def run([event, ref]) do
    directory = Bob.Directory.new()
    Logger.info("Using directory #{directory}")
    Bob.Script.run({:script, "elixir_guides_github.sh"}, [event, ref], directory)
  end

  def equal?(args1, args2), do: args1 == args2
end
