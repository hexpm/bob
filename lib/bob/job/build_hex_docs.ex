defmodule Bob.Job.BuildHexDocs do
  require Logger

  def run([event, ref]) do
    if run?(ref) do
      directory = Bob.Directory.new()
      Logger.info("Using directory #{directory}")
      Bob.Script.run({:script, "hex_docs.sh"}, [event, ref], directory)
    else
      Logger.info("Skipping hexpm/hex/#{ref}")
    end
  end

  def equal?(_, _), do: false

  def similar?(args, args), do: true
  def similar?(_, _), do: false

  defp run?("v" <> string), do: match?({:ok, _}, Version.parse(string))
  defp run?(_), do: false
end
