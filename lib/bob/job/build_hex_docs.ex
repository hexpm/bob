defmodule Bob.Job.BuildHexDocs do
  require Logger

  def run([event, ref_name | _]) do
    if run?(ref_name) do
      directory = Bob.Directory.new()
      Logger.info("Using directory #{directory}")
      Bob.Script.run({:script, "hex/hex_docs.sh"}, [event, ref_name], directory)
    else
      Logger.info("Skipping hexpm/hex/#{ref_name}")
    end
  end

  def equal?(_, _), do: false

  def similar?(args, args), do: true
  def similar?(_, _), do: false

  defp run?("v" <> string), do: match?({:ok, _}, Version.parse(string))
  defp run?(_), do: false
end
