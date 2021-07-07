defmodule Bob.DockerHub.OSVersionsSelector do
  @alpine_minor_versions ["3.14", "3.13"]

  def select(:alpine, tags) do
    tags
    |> Enum.map(fn {version, _} -> version end)
    |> Enum.filter(fn version -> starts_with_any?(version, @alpine_minor_versions) end)
    |> Enum.flat_map(fn version ->
      case Version.parse(version) do
        {:ok, version} -> [version]
        :error -> []
      end
    end)
    |> Enum.reduce(%{}, fn version, acc ->
      Map.update(acc, "#{version.major}.#{version.minor}", version, fn current ->
        higher_version(current, version)
      end)
    end)
    |> Map.values()
    |> Enum.sort(:desc)
    |> Enum.map(fn version -> to_string(version) end)
  end

  defp starts_with_any?(str, prefixes) do
    Enum.any?(prefixes, fn prefix ->
      String.starts_with?(str, prefix)
    end)
  end

  defp higher_version(version1, version2) do
    case Version.compare(version1, version2) do
      :gt -> version1
      :lt -> version2
      _ -> version1
    end
  end
end
