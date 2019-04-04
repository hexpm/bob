defmodule Bob.Job.BuildElixir do
  require Logger

  def run(["push", ref_name, ref]) do
    if build_ref?(ref_name) do
      directory = Bob.Directory.new()
      args = ["push", ref_name, ref] ++ Enum.reverse(elixir_to_otp(ref_name))
      Logger.info("Using directory #{directory}")
      Bob.Script.run({:script, "elixir.sh"}, args, directory)
    end
  end

  def run(["delete", ref_name, _ref]) do
    directory = Bob.Directory.new()
    args = ["delete", ref_name]
    Logger.info("Using directory #{directory}")
    Bob.Script.run({:script, "elixir.sh"}, args, directory)
  end

  def equal?(_, _), do: false

  def similar?(args, args), do: true
  def similar?(_, _), do: false

  defp build_ref?("v" <> version) do
    match?({:ok, _}, Version.parse(version)) or match?({:ok, _}, Version.parse(version <> ".0"))
  end

  defp build_ref?("master"), do: true
  defp build_ref?(_), do: false

  defp elixir_to_otp(ref) do
    case ref do
      "v0" <> _ -> ["17.3"]
      "v1.0.0" -> ["17.3"]
      "v1.0.1" -> ["17.3"]
      "v1.0.2" -> ["17.3"]
      "v1.0.3" -> ["17.3"]
      "v1.0.4" -> ["17.5"]
      "v1.0.5" -> ["17.5"]
      "v1.0" <> _ -> ["17.3", "18.3"]
      "v1.1" <> _ -> ["17.5", "18.3"]
      "v1.2.0" -> ["18.3"]
      "v1.2.1" -> ["18.3"]
      "v1.2.2" -> ["18.3"]
      "v1.2.3" -> ["18.3"]
      "v1.2.4" -> ["18.3"]
      "v1.2.5" -> ["18.3"]
      "v1.2.6" -> ["18.3"]
      "v1.2" <> _ -> ["18.3", "19.3"]
      "v1.3" <> _ -> ["18.3", "19.3"]
      "v1.4.0" -> ["18.3", "19.3"]
      "v1.4.1" -> ["18.3", "19.3"]
      "v1.4.2" -> ["18.3", "19.3"]
      "v1.4.3" -> ["18.3", "19.3"]
      "v1.4.4" -> ["18.3", "19.3"]
      "v1.4" <> _ -> ["18.3", "19.3", "20.3"]
      "v1.5" <> _ -> ["18.3", "19.3", "20.3"]
      "v1.6.0" -> ["19.3", "20.3"]
      "v1.6.1" -> ["19.3", "20.3"]
      "v1.6.2" -> ["19.3", "20.3"]
      "v1.6.3" -> ["19.3", "20.3"]
      "v1.6.4" -> ["19.3", "20.3"]
      "v1.6" <> _ -> ["19.3", "20.3", "21.2"]
      "v1.7" <> _ -> ["19.3", "20.3", "21.2"]
      # Assume all other branches support the same versions as master
      _ -> ["20.3", "21.2"]
    end
  end
end
