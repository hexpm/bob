defmodule Bob.GitHub do
  @github_url "https://api.github.com/"
  @bucket "s3.hex.pm"

  def diff(repo, build_path) do
    existing = fetch_repo_refs(repo)
    built = fetch_built_refs(build_path)

    Enum.filter(existing, fn {name, ref} ->
      case Map.fetch(built, name) do
        {:ok, ^ref} -> false
        _other -> true
      end
    end)
  end

  def fetch_repo_refs(repo) do
    branches = github_request(@github_url <> "repos/#{repo}/branches")
    tags = github_request(@github_url <> "repos/#{repo}/tags")
    response_to_refs(branches) ++ response_to_refs(tags)
  end

  defp response_to_refs(response) do
    Enum.map(response, &{&1["name"], &1["commit"]["sha"]})
  end

  defp github_request(url) do
    user = Application.get_env(:bob, :github_user)
    token = Application.get_env(:bob, :github_token)

    opts = [:with_body, basic_auth: {user, token}]
    {:ok, 200, headers, body} = :hackney.request(:get, url, [], "", opts)
    body = Jason.decode!(body)

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

  # TODO: Use S3 object metadata
  defp fetch_built_refs(build_path) do
    key = Path.join(build_path, "builds.txt")

    {:ok, %{body: body}} = ExAws.S3.get_object(@bucket, key, []) |> ExAws.request()

    String.split(body, "\n", trim: true)
    |> Map.new(&line_to_ref/1)
  end

  defp line_to_ref(line) do
    destructure [ref_name, ref], String.split(line, " ", trim: true)
    {ref_name, ref}
  end
end
