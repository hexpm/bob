defmodule Bob.Job.HexDocsChecker do
  @repo "hexpm/hex"
  @file_regex ~r"^docs/hex-(.*).tar.gz$"

  def run([]) do
    Enum.each(diff(), fn {ref_name, _ref} ->
      Bob.Queue.run(Bob.Job.BuildHexDocs, [ref_name])
    end)
  end

  def equal?(_, _), do: true

  def similar?(_, _), do: true

  defp build_ref?("v" <> version) do
    case Version.parse(version) do
      {:ok, version} -> Version.compare(version, "0.17.0") in [:eq, :gt]
      :error -> false
    end
  end

  defp build_ref?(_), do: false

  defp diff() do
    existing =
      Bob.Repo.list_files("docs/hex-")
      |> Enum.map(fn file ->
        [version] = Regex.run(@file_regex, file, capture: :all_but_first)
        "v" <> version
      end)
      |> MapSet.new()

    Enum.filter(Bob.GitHub.fetch_repo_refs(@repo), fn {ref_name, _ref} ->
      build_ref?(ref_name) and ref_name not in existing
    end)
  end
end
