defmodule Bob.FakeGitHub do
  def fetch_repo_refs(repo) do
    :persistent_term.get({__MODULE__, repo}, [])
  end

  def stub_refs(repo, refs) do
    :persistent_term.put({__MODULE__, repo}, refs)
  end

  def reset() do
    for {{__MODULE__, _repo} = key, _value} <- :persistent_term.get() do
      :persistent_term.erase(key)
    end
  end
end
