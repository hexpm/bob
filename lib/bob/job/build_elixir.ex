defmodule Bob.Job.BuildElixir do
  require Logger

  def run(ref_name, ref) do
    directory = Bob.Directory.new()
    args = [ref_name, ref] ++ Enum.reverse(elixir_to_otp(ref_name))
    Logger.info("Using directory #{directory}")
    Bob.Script.run({:script, "elixir/elixir.sh"}, args, directory)
  end

  def elixir_to_otp(ref) do
    case ref do
      "v0" <> _ -> ["17.3"]
      "v1.0.0-" <> _ -> ["17.3"]
      "v1.0." <> patch when patch in ~w(0 1 2 3) -> ["17.3"]
      "v1.0.4" -> ["17.5"]
      "v1.0.5" -> ["17.5"]
      "v1.0" <> _ -> ["17.3", "18.3"]
      "v1.1." <> _ -> ["17.5", "18.3"]
      "v1.1" -> ["17.5", "18.3"]
      "v1.2." <> patch when patch in ~w(0-rc.0 0-rc.1 0 1 2 3 4 5 6) -> ["18.3"]
      "v1.2." <> _ -> ["18.3", "19.3"]
      "v1.2" -> ["18.3", "19.3"]
      "v1.3" <> _ -> ["18.3", "19.3"]
      "v1.4." <> patch when patch in ~w(0-rc.0 0-rc.1 0 1 2 3 4) -> ["18.3", "19.3"]
      "v1.4." <> _ -> ["18.3", "19.3", "20.3"]
      "v1.4" <> _ -> ["18.3", "19.3", "20.3"]
      "v1.5." <> _ -> ["18.3", "19.3", "20.3"]
      "v1.5" <> _ -> ["18.3", "19.3", "20.3"]
      "v1.6." <> patch when patch in ~w(0-rc.0 0-rc.1 0 1 2 3 4 5) -> ["19.3", "20.3"]
      "v1.6." <> _ -> ["19.3", "20.3", "21.3"]
      "v1.6" -> ["19.3", "20.3", "21.3"]
      "v1.7." <> _ -> ["19.3", "20.3", "21.3", "22.3"]
      "v1.7" -> ["19.3", "20.3", "21.3", "22.3"]
      "v1.8." <> _ -> ["20.3", "21.3", "22.3"]
      "v1.8" -> ["20.3", "21.3", "22.3"]
      "v1.9." <> _ -> ["20.3", "21.3", "22.3"]
      "v1.9" -> ["20.3", "21.3", "22.3"]
      "v1.10." <> patch when patch in ~w(0-rc.0 0 1 2) -> ["21.3", "22.3"]
      "v1.10." <> _ -> ["21.3", "22.3", "23.0"]
      "v1.10" -> ["21.3", "22.3", "23.0"]
      # Assume all other branches support the same versions as master
      _ -> ["21.3", "22.3", "23.0"]
    end
  end

  def priority(), do: 2
  def weight(), do: 3
end
