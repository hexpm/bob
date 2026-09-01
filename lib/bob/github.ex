defmodule Bob.GitHub do
  @github_url "https://api.github.com/"

  def fetch_repo_refs(repo) do
    branches = github_request(@github_url <> "repos/#{repo}/branches?per_page=100")
    response_to_refs(branches) ++ fetch_repo_tags(repo)
  end

  def fetch_repo_tags(repo) do
    repo
    |> tags_url()
    |> github_request()
    |> response_to_refs()
  end

  def fetch_repo_releases(repo) do
    repo
    |> releases_url()
    |> github_request()
  end

  # Releases come back newest-first, so the first page is enough to find
  # anything published recently without paging through years of history.
  def fetch_recent_releases(repo) do
    {body, _headers} =
      repo
      |> releases_url()
      |> github_get()

    body
  end

  defp response_to_refs(response) do
    Enum.map(response, fn item ->
      {:binary.copy(item["name"]), :binary.copy(item["commit"]["sha"])}
    end)
  end

  defp github_request(url) do
    {body, headers} = github_get(url)

    if url = next_link(headers) do
      body ++ github_request(url)
    else
      body
    end
  end

  defp github_get(url) do
    user = Application.get_env(:bob, :github_user)
    token = Application.get_env(:bob, :github_token)

    opts = if user && token, do: [basic_auth: {user, token}], else: []

    result = Bob.HTTP.retry("GitHub #{url}", fn -> Bob.HTTP.request(:get, url, [], "", opts) end)

    case result do
      {:ok, 200, headers, body} ->
        {JSON.decode!(body), headers}

      {:ok, status, _headers, _body} ->
        raise "GitHub #{url} returned status #{status} after retries"

      {:error, reason} ->
        raise "GitHub #{url} failed after retries: #{inspect(reason)}"
    end
  end

  defp next_link(headers) do
    headers = Map.new(headers, fn {key, value} -> {String.downcase(key), value} end)
    links = Map.get(headers, "link", "") |> String.split(",", trim: true)

    Enum.find_value(links, fn link ->
      [link, rel] = String.split(link, ";", trim: true, parts: 2)

      if String.trim(rel) == "rel=\"next\"" do
        link
        |> String.trim()
        |> String.trim_leading("<")
        |> String.trim_trailing(">")
      end
    end)
  end

  defp tags_url(repo), do: @github_url <> "repos/#{repo}/tags?per_page=100"

  defp releases_url(repo), do: @github_url <> "repos/#{repo}/releases?per_page=100"
end
