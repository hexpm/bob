defmodule Bob.GitHub do
  @github_url "https://api.github.com/"
  @bucket "s3.hex.pm"

  def diff(repo, linux) do
    existing = fetch_repo_refs(repo)
    built = fetch_built_refs(repo, linux)

    Enum.filter(existing, fn {name, ref} ->
      case Map.fetch(built, name) do
        {:ok, ^ref} -> false
        _other -> valid_ref_name?(repo, name)
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
    body = Poison.decode!(body)

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
  defp fetch_built_refs(repo, linux) do
    key = repo_to_path(repo, linux) <> "/builds.txt"

    {:ok, %{body: body}} = ExAws.S3.get_object(@bucket, key, []) |> ExAws.request()

    String.split(body, "\n", trim: true)
    |> Map.new(&List.to_tuple(String.split(&1, " ", parts: 2, trim: true)))
  end

  defp repo_to_path("erlang/otp", linux), do: "builds/otp/#{linux}"

  defp valid_ref_name?("erlang/otp", "OTP-18.0-rc2"), do: false
  defp valid_ref_name?("erlang/otp", "OTP_" <> _), do: false
  defp valid_ref_name?("erlang/otp", "OTP-" <> _), do: true
  defp valid_ref_name?("erlang/otp", "maint-r" <> _), do: false
  defp valid_ref_name?("erlang/otp", "maint" <> _), do: true
  defp valid_ref_name?("erlang/otp", "master" <> _), do: true
  defp valid_ref_name?("erlang/otp", _), do: false
end
