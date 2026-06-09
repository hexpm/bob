defmodule Bob.DockerHub do
  @dockerhub_url "https://hub.docker.com/"

  def auth(username, password) do
    url = @dockerhub_url <> "v2/users/login/"
    headers = [{"content-type", "application/json"}]
    body = %{username: username, password: password}
    opts = [recv_timeout: 10_000]

    {:ok, 200, _headers, body} =
      Bob.HTTP.retry("DockerHub #{url}", fn ->
        Bob.HTTP.request(:post, url, headers, JSON.encode!(body), opts)
      end)

    result = JSON.decode!(body)
    Application.put_env(:bob, :dockerhub_token, result["token"])
  end

  @doc """
  Pages every tag of `repo` from Docker Hub, invoking `on_page` with each page's
  `{tag, archs, built_at}` list as it arrives. Returns `:ok` once the full set is
  fetched or `:error` if any page failed, so the caller can avoid applying a
  partial set. Pages stream through `on_page` rather than accumulating, so the
  response set is never held in memory in full.
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
    opts = [recv_timeout: 20_000]

    result =
      Bob.HTTP.retry("DockerHub #{url}", fn ->
        Bob.HTTP.request(:get, url, headers, "", opts)
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
    opts = [recv_timeout: 20_000]

    result =
      Bob.HTTP.retry("DockerHub #{url}", fn ->
        Bob.HTTP.request(:delete, url, headers, "", opts)
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
    images =
      Enum.reject(result["images"] || [], fn image ->
        image["digest"] in [nil, ""] or image["architecture"] in [nil, ""]
      end)

    built_at = docker_hub_timestamp(result, images)

    if images == [] or is_nil(built_at) do
      nil
    else
      # DockerHub returns dupes sometimes?
      archs = images |> Enum.map(&:binary.copy(&1["architecture"])) |> Enum.uniq()
      {:binary.copy(result["name"]), archs, built_at}
    end
  end

  defp docker_hub_timestamp(result, images) do
    parse_timestamp(result["last_updated"]) ||
      images
      |> Enum.map(&parse_timestamp(&1["last_pushed"]))
      |> Enum.reject(&is_nil/1)
      |> Enum.max_by(&DateTime.to_unix(&1, :microsecond), fn -> nil end)
  end

  defp parse_timestamp(value) when value in [nil, ""], do: nil

  defp parse_timestamp(value) when is_binary(value) do
    with {:error, _reason} <- DateTime.from_iso8601(value) do
      parse_naive_timestamp(value)
    else
      {:ok, datetime, _offset} -> force_microsecond_precision(datetime)
    end
  end

  defp parse_naive_timestamp(value) do
    with {:ok, datetime} <- NaiveDateTime.from_iso8601(value) do
      datetime
      |> NaiveDateTime.truncate(:microsecond)
      |> DateTime.from_naive!("Etc/UTC")
      |> force_microsecond_precision()
    else
      {:error, _reason} -> nil
    end
  end

  defp force_microsecond_precision(%DateTime{} = datetime) do
    %{datetime | microsecond: {elem(datetime.microsecond, 0), 6}}
  end
end
