defmodule Bob.DockerHub do
  @dockerhub_url "https://hub.docker.com/"

  def auth(username, password) do
    url = @dockerhub_url <> "v2/users/login/"
    headers = [{"content-type", "application/json"}]
    body = %{username: username, password: password}
    opts = [:with_body, recv_timeout: 10_000]

    {:ok, 200, _headers, body} =
      Bob.HTTP.retry("DockerHub #{url}", fn ->
        :hackney.request(:post, url, headers, JSON.encode!(body), opts)
      end)

    result = JSON.decode!(body)
    Application.put_env(:bob, :dockerhub_token, result["token"])
  end

  @doc """
  Pages every tag of `repo` from Docker Hub, invoking `on_page` with each page's
  `{tag, archs}` list as it arrives. Returns `:ok` once the full set is fetched
  or `:error` if any page failed, so the caller can avoid applying a partial set.
  Pages stream through `on_page` rather than accumulating, so the response set is
  never held in memory in full.
  """
  def stream_repo_tags(repo, on_page) do
    url = @dockerhub_url <> "v2/repositories/#{repo}/tags?page=${page}&page_size=100"
    {:ok, server} = Bob.DockerHub.Pager.start_link(url, on_page)

    case Bob.DockerHub.Pager.wait(server) do
      :ok -> :ok
      {:error, _reason} -> :error
    end
  end

  def fetch_tag(repo, tag) do
    url = @dockerhub_url <> "v2/repositories/#{repo}/tags/#{tag}"
    headers = headers()
    opts = [:with_body, recv_timeout: 20_000]

    result =
      Bob.HTTP.retry("DockerHub #{url}", fn ->
        :hackney.request(:get, url, headers, "", opts)
      end)

    case result do
      {:ok, 200, _headers, body} ->
        parse(JSON.decode!(body))

      {:ok, 404, _headers, _body} ->
        nil
    end
  end

  def delete_tag(repo, tag) do
    url = @dockerhub_url <> "v2/repositories/#{repo}/tags/#{tag}"
    headers = headers()
    opts = [:with_body, recv_timeout: 20_000]

    result =
      Bob.HTTP.retry("DockerHub #{url}", fn ->
        :hackney.request(:delete, url, headers, "", opts)
      end)

    case result do
      {:ok, 204, _headers, _body} -> :ok
      {:ok, 404, _headers, _body} -> :ok
    end
  end

  def headers() do
    if token = Application.get_env(:bob, :dockerhub_token) do
      [{"authorization", "JWT #{token}"}]
    else
      []
    end
  end

  def parse(result) do
    # Reject corrupt images
    images = Enum.reject(result["images"], &(&1["digest"] in [nil, ""]))

    if images == [] do
      nil
    else
      # DockerHub returns dupes sometimes?
      archs = result["images"] |> Enum.map(&:binary.copy(&1["architecture"])) |> Enum.uniq()
      {:binary.copy(result["name"]), archs}
    end
  end
end
