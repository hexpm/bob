defmodule Bob.GitHub do
  @github_url "https://api.github.com/"

  def fetch_repo_refs(repo) do
    branches = github_request(@github_url <> "repos/#{repo}/branches")
    tags = github_request(@github_url <> "repos/#{repo}/tags")
    response_to_refs(branches) ++ response_to_refs(tags)
  end

  defp response_to_refs(response) do
    Enum.map(response, fn item ->
      {:binary.copy(item["name"]), :binary.copy(item["commit"]["sha"])}
    end)
  end

  defp github_request(url) do
    user = Application.get_env(:bob, :github_user)
    token = Application.get_env(:bob, :github_token)

    opts = [basic_auth: {user, token}]

    {:ok, 200, headers, body} =
      Bob.HTTP.retry("GitHub #{url}", fn -> Bob.HTTP.request(:get, url, [], "", opts) end)

    body = JSON.decode!(body)

    if url = next_link(headers) do
      body ++ github_request(url)
    else
      body
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
end
