defmodule Bob.Job.ElixirGuidesChecker do
  @repo "elixir-lang/elixir-lang.github.com"

  def run() do
    for {"main", ref} <- Bob.GitHub.fetch_repo_refs(@repo),
        current_ref = Bob.Repo.fetch_file("guides/elixir/ref.txt"),
        String.trim(current_ref) != ref,
        do: Bob.Queue.add(Bob.Job.BuildElixirGuides, [ref])
  end

  def priority(), do: 1
  def weight(), do: 1
end
