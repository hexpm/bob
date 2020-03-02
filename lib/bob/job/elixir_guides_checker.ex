defmodule Bob.Job.ElixirGuidesChecker do
  @repo "elixir-lang/elixir-lang.github.com"

  def run([]) do
    for {"master", ref} <- Bob.GitHub.fetch_repo_refs(@repo),
        current_ref = Bob.Repo.fetch_file("guides/elixir/ref.txt"),
        String.trim(current_ref) != ref,
        do: Bob.Queue.queue(Bob.Job.BuildElixirGuides, [ref])
  end

  def equal?(_, _), do: true

  def similar?(_, _), do: true
end
