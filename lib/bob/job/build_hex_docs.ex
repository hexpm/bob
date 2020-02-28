defmodule Bob.Job.BuildHexDocs do
  require Logger

  def run([ref_name]) do
    directory = Bob.Directory.new()
    Logger.info("Using directory #{directory}")
    Bob.Script.run({:script, "hex/hex_docs.sh"}, [ref_name], directory)
  end

  def equal?(_, _), do: false

  def similar?(args, args), do: true
  def similar?(_, _), do: false
end
