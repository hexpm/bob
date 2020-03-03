defmodule Bob.Job.QueueChecker do
  def run([:master]) do
    local_queue()
  end

  def run([:agent]) do
    local_queue()
    remote_queue()
  end

  defp local_queue() do
    Enum.each(Application.get_env(:bob, :local_jobs), fn module ->
      case Bob.Queue.start(module) do
        {:ok, {id, args}} ->
          Bob.Runner.run(module, args, local_success(id), local_failure(id))

        :error ->
          :ok
      end
    end)
  end

  defp remote_queue() do
    Enum.each(start_request(), fn {id, {module, args}} ->
      Bob.Runner.run(module, args, remote_success(id), remote_failure(id))
    end)
  end

  defp local_success(id) do
    fn -> Bob.Queue.success(id) end
  end

  defp local_failure(id) do
    fn -> Bob.Queue.failure(id) end
  end

  defp remote_success(id) do
    fn -> done_request(:success, id) end
  end

  defp remote_failure(id) do
    fn -> done_request(:failure, id) end
  end

  defp done_request(type, id) do
    url = Application.get_env(:bob, :master_url) <> "/queue/#{type}"
    secret = Application.get_env(:bob, :agent_secret)

    headers = [{"authorization", secret}, {"content-type", "application/vnd.bob+erlang"}]
    body = Bob.Plug.ErlangFormat.encode_to_iodata!(%{id: id})
    {:ok, 204, _headers} = :hackney.request(:post, url, headers, body, [])
    :ok
  end

  defp start_request() do
    url = Application.get_env(:bob, :master_url) <> "/queue/start"
    secret = Application.get_env(:bob, :agent_secret)
    remote_jobs = Application.get_env(:bob, :remote_jobs)

    opts = [:with_body]
    headers = [{"authorization", secret}, {"content-type", "application/vnd.bob+erlang"}]
    body = Bob.Plug.ErlangFormat.encode_to_iodata!(%{jobs: remote_jobs})
    {:ok, 200, _headers, body} = :hackney.request(:post, url, headers, body, opts)
    {:ok, %{jobs: jobs}} = Bob.Plug.ErlangFormat.decode(body)
    jobs
  end
end
