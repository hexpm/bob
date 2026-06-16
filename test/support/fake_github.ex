defmodule Bob.FakeGitHub do
  def fetch_repo_refs(repo) do
    :persistent_term.get({__MODULE__, repo}, [])
  end

  def fetch_repo_tags(repo) do
    fetch_repo_refs(repo)
  end

  def fetch_repo_releases(repo) do
    :persistent_term.get({__MODULE__, {:releases, repo}}, [])
  end

  def fetch_recent_releases(repo) do
    fetch_repo_releases(repo)
  end

  def stub_refs(repo, refs) do
    :persistent_term.put({__MODULE__, repo}, refs)
  end

  def stub_releases(repo, releases) do
    :persistent_term.put({__MODULE__, {:releases, repo}}, releases)
  end

  def reset() do
    for {{__MODULE__, _key} = key, _value} <- :persistent_term.get() do
      :persistent_term.erase(key)
    end
  end
end
