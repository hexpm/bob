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

  def fetch_repo_tags(repo) do
    url = @dockerhub_url <> "v2/repositories/#{repo}/tags?page=${page}&page_size=100"
    {:ok, server} = Bob.DockerHub.Pager.start_link(url)
    Bob.DockerHub.Pager.wait(server)
  end

  def fetch_repo_tags_from_cache(repo) do
    :ok =
      Bob.DockerHub.Cache.lookup(repo, fn on_result ->
        url = @dockerhub_url <> "v2/repositories/#{repo}/tags?page=${page}&page_size=100"
        {:ok, server} = Bob.DockerHub.Pager.start_link(url, on_result)
        Bob.DockerHub.Pager.wait(server)
      end)

    Bob.DockerHub.Cache.stream(repo)
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
