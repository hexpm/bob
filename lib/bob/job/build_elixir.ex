defmodule Bob.Job.BuildElixir do
  require Logger

  def run(ref_name, ref) do
    directory = Bob.Directory.new()
    args = [ref_name, ref] ++ Enum.reverse(elixir_to_otp(ref_name))
    Logger.info("Using directory #{directory}")
    Bob.Script.run({:script, "elixir/elixir.sh"}, args, directory)
  end

  def elixir_to_otp(ref_name) do
    version = ref_to_version(ref_name)

    cond do
      version_gte(version, "1.15.0-0") -> ["24.3", "25.0", "26.0"]
      version_gte(version, "1.14.4-0") -> ["23.3", "24.3", "25.0", "26.0"]
      version_gte(version, "1.14.0-0") -> ["23.3", "24.3", "25.0"]
      version_gte(version, "1.13.0-0") -> ["23.3", "24.3", "25.0"]
      version_gte(version, "1.12.0-0") -> ["22.3", "23.3", "24.3"]
      version_gte(version, "1.11.4") -> ["21.3", "22.3", "23.3", "24.3"]
      version_gte(version, "1.10.3") -> ["21.3", "22.3", "23.3"]
      version_gte(version, "1.10.0-rc.0") -> ["21.3", "22.3"]
      version_gte(version, "1.8.0-rc.0") -> ["20.3", "21.3", "22.3"]
      version_gte(version, "1.7.0-rc.0") -> ["19.3", "20.3", "21.3", "22.3"]
      version_gte(version, "1.6.6") -> ["19.3", "20.3", "21.3"]
      version_gte(version, "1.6.0-rc.0") -> ["19.3", "20.3"]
      version_gte(version, "1.4.5") -> ["18.3", "19.3", "20.3"]
      version_gte(version, "1.2.6") -> ["18.3", "19.3"]
      version_gte(version, "1.2.0-rc.0") -> ["18.3"]
      version_gte(version, "1.0.5") -> ["17.5", "18.3"]
      version_gte(version, "1.0.4") -> ["17.5"]
      true -> ["17.3"]
    end
  end

  defp version_gte("main", _base), do: true

  defp version_gte(version, base_version) do
    case Version.compare(version, base_version) do
      :lt -> false
      _gte -> true
    end
  end

  defp ref_to_version("v" <> version) do
    # Version.Parser cannot parse backport maintenance tags (eg 1.10)
    # as it doesn't have a patch number.
    # we add a large patch to be able to use `Version.compare/2`
    case String.match?(version, ~r/^\d+\.\d+$/) do
      true -> "#{version}.99999"
      _otherwise -> version
    end
  end

  defp ref_to_version(_not_a_version), do: "main"

  def priority(), do: 2
  def weight(), do: 3
end
