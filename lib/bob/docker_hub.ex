defmodule Bob.DockerHub do
  alias Bob.DockerHub.RateLimiter

  @dockerhub_url "https://hub.docker.com/"

  # Caps re-attempts after a 429 so a permanently throttled IP can't loop forever;
  # each attempt first feeds the limiter, which blocks until the window resets.
  @max_rate_limit_retries 20

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
  `{tag, archs, built_at, last_pulled}` list as it arrives. Returns `:ok` once
  the full set is fetched or `:error` if any page failed, so the caller can avoid
  applying a partial set. Pages stream through `on_page` rather than accumulating,
  so the response set is never held in memory in full.
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

  @doc """
  Deletes a tag on Docker Hub, paced by the shared rate limiter. A missing tag
  (404) counts as success so the cleanup is idempotent across retries. Returns
  `{:error, _}` for any other outcome so the caller can skip the tag and retry it
  on a later run rather than crash the batch.
  """
  def delete_tag(repo, tag) do
    url = @dockerhub_url <> "v2/repositories/#{repo}/tags/#{tag}"

    case paced_request(:delete, url) do
      {:ok, status, _headers, _body} when status in [204, 404] -> :ok
      other -> {:error, other}
    end
  end

  @doc """
  Sends `method` to `url` paced by the shared rate limiter: acquires a slot
  (blocking until the window has budget), feeds the response back so the gate
  tracks the limit, and waits out 429s up to the retry cap. Returns the final
  non-429 result for the caller to match on. Every outcome reports to the
  limiter — a response without usable rate headers, or a transport error,
  releases the calibration probe's slot — so a failed request can't leave the
  gate shut for every later caller.
  """
  def paced_request(method, url), do: paced_request(method, url, 0)

  defp paced_request(method, url, attempts) do
    RateLimiter.acquire()

    result =
      Bob.HTTP.retry(
        "DockerHub #{url}",
        fn -> Bob.HTTP.request(method, url, headers(), "", recv_timeout: 20_000) end,
        retry_rate_limit?: false
      )

    case result do
      {:ok, 429, response_headers, _body} when attempts < @max_rate_limit_retries ->
        RateLimiter.throttle(response_headers)
        paced_request(method, url, attempts + 1)

      {:ok, _status, response_headers, _body} ->
        RateLimiter.observe(response_headers)
        result

      {:error, _reason} ->
        RateLimiter.observe([])
        result
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
      {:binary.copy(result["name"]), archs, built_at, last_pulled(result)}
    end
  end

  # `tag_last_pulled` is the last time Docker Hub served this tag's manifest. It
  # is null for a tag that has never been pulled, and historically a zero
  # sentinel; both map to nil so callers can treat "never pulled" uniformly.
  defp last_pulled(result) do
    case result["tag_last_pulled"] do
      "0001-01-01" <> _ -> nil
      value -> parse_timestamp(value)
    end
  end

  defp docker_hub_timestamp(result, images) do
    parse_timestamp(result["last_updated"]) ||
      images
      |> Enum.map(&parse_timestamp(&1["last_pushed"]))
      |> Enum.reject(&is_nil/1)
      |> Enum.max_by(&DateTime.to_unix(&1, :microsecond), fn -> nil end)
  end

  defp parse_timestamp(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} ->
        force_microsecond_precision(datetime)

      {:error, _reason} ->
        parse_naive_timestamp(value)
    end
  end

  defp parse_timestamp(_value), do: nil

  defp parse_naive_timestamp(value) do
    case NaiveDateTime.from_iso8601(value) do
      {:ok, datetime} ->
        datetime
        |> DateTime.from_naive!("Etc/UTC")
        |> force_microsecond_precision()

      {:error, _reason} ->
        nil
    end
  end

  defp force_microsecond_precision(%DateTime{} = datetime) do
    %{datetime | microsecond: {elem(datetime.microsecond, 0), 6}}
  end
end
