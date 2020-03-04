defmodule Bob.RemoteQueue do
  def start(num) do
    if Application.get_env(:bob, :master?) do
      local_queue(num)
    else
      jobs = local_queue(num)
      jobs ++ remote_queue(num - length(jobs))
    end
  end

  def success({:local, id}) do
    Bob.Queue.success(id)
  end

  def success({:remote, id}) do
    done_request(:success, id)
  end

  def failure({:local, id}) do
    Bob.Queue.failure(id)
  end

  def failure({:remote, id}) do
    done_request(:failure, id)
  end

  defp local_queue(num) do
    Application.get_env(:bob, :local_jobs)
    |> Enum.shuffle()
    |> Stream.flat_map(fn module ->
      case Bob.Queue.start(module) do
        {:ok, {id, args}} -> [{{:local, id}, module, args}]
        :error -> []
      end
    end)
    |> Enum.take(num)
  end

  defp remote_queue(num) when num > 0 do
    Application.get_env(:bob, :remote_jobs)
    |> Enum.shuffle()
    |> start_request(num)
    |> Enum.map(fn {id, {module, args}} ->
      {{:remote, id}, module, args}
    end)
  end

  defp remote_queue(_num) do
    []
  end

  defp done_request(type, id) do
    url = Application.get_env(:bob, :master_url) <> "/queue/#{type}"
    secret = Application.get_env(:bob, :agent_secret)

    headers = [{"authorization", secret}, {"content-type", "application/vnd.bob+erlang"}]
    body = Bob.Plug.ErlangFormat.encode_to_iodata!(%{id: id})
    {:ok, 204, _headers} = :hackney.request(:post, url, headers, body, [])
    :ok
  end

  defp start_request(remote_jobs, num) do
    url = Application.get_env(:bob, :master_url) <> "/queue/start"
    secret = Application.get_env(:bob, :agent_secret)

    opts = [:with_body]
    headers = [{"authorization", secret}, {"content-type", "application/vnd.bob+erlang"}]
    body = Bob.Plug.ErlangFormat.encode_to_iodata!(%{jobs: remote_jobs, num: num})
    {:ok, 200, _headers, body} = :hackney.request(:post, url, headers, body, opts)
    {:ok, %{jobs: jobs}} = Bob.Plug.ErlangFormat.decode(body)
    jobs
  end
end
