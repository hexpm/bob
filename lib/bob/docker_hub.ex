defmodule Bob.DockerHub do
  @dockerhub_url "https://hub.docker.com/"

  def fetch_repo_tags(repo) do
    (@dockerhub_url <> "v2/repositories/#{repo}/tags?page_size=100")
    |> dockerhub_request()
    |> response_to_tags()
  end

  defp response_to_tags(response) do
    Enum.map(response, & &1["name"])
  end

  defp dockerhub_request(url) do
    opts = [:with_body, recv_timeout: 10_000]
    {:ok, 200, _headers, body} = :hackney.request(:get, url, [], "", opts)
    body = Jason.decode!(body)

    if url = body["next"] do
      body["results"] ++ dockerhub_request(url)
    else
      body["results"]
    end
  end
end
