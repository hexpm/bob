defmodule Bob.DockerHub do
  @dockerhub_url "https://hub.docker.com/"

  def fetch_repo_tags(repo) do
    (@dockerhub_url <> "v2/repositories/#{repo}/tags?page_size=100")
    |> dockerhub_request()
    |> parse_response()
  end

  defp parse_response(response) do
    Enum.flat_map(response, fn result ->
      # Reject corrupt images
      images = Enum.reject(result["images"], &(&1["digest"] in [nil, ""]))

      if images == [] do
        []
      else
        # DockerHub returns dupes sometimes?
        archs = Enum.uniq(Enum.map(result["images"], & &1["architecture"]))
        [{result["name"], archs}]
      end
    end)
  end

  defp dockerhub_request(url) do
    opts = [:with_body, recv_timeout: 10_000]

    {:ok, 200, _headers, body} =
      Bob.HTTP.retry("DockerHub #{url}", fn -> :hackney.request(:get, url, [], "", opts) end)

    body = Jason.decode!(body)

    if url = body["next"] do
      body["results"] ++ dockerhub_request(url)
    else
      body["results"]
    end
  end
end
