defmodule Bob.Job.BuildHexDocs do
  require Logger

  def run(ref_name) do
    directory = Bob.Directory.new()
    Logger.info("Using directory #{directory}")
    Bob.Script.run({:script, "hex/hex_docs.sh"}, [ref_name], directory)
  end

  def priority(), do: 2
  def weight(), do: 3
end
