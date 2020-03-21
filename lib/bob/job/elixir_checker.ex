defmodule Bob.Job.ElixirChecker do
  @repo "elixir-lang/elixir"

  def run() do
    for {ref_name, ref} <- Bob.GitHub.diff(@repo, "builds/elixir"),
        build_ref?(ref_name),
        do: Bob.Queue.add(Bob.Job.BuildElixir, [ref_name, ref])
  end

  def priority(), do: 1
  def weight(), do: 1

  defp build_ref?("master"), do: true
  defp build_ref?("v0." <> _), do: false

  defp build_ref?("v" <> version) do
    match?({:ok, _}, Version.parse(version)) or match?({:ok, _}, Version.parse(version <> ".0"))
  end

  defp build_ref?(_), do: false
end
