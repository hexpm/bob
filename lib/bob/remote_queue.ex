defmodule Bob.RemoteQueue do
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

  def local_queue(num) when num > 0 do
    Application.get_env(:bob, :local_jobs)
    |> Enum.shuffle()
    |> cycle(num)
    |> Stream.flat_map(fn module ->
      case Bob.Queue.start(module) do
        {:ok, {id, args}} -> [{{:local, id}, module, args}]
        :error -> []
      end
    end)
    |> Enum.take(num)
  end

  def local_queue(_num) do
    []
  end

  def remote_queue(num) when num > 0 do
    Application.get_env(:bob, :remote_jobs)
    |> Enum.shuffle()
    |> start_request(num)
    |> Enum.map(fn {id, {module, args}} ->
      {{:remote, id}, module, args}
    end)
  end

  def remote_queue(_num) do
    []
  end

  defp cycle([], _times), do: []

  defp cycle(enum, times) do
    # Work around stream bug
    enum
    |> Stream.cycle()
    |> Enum.take(Enum.count(enum) * times)
  end

  defp done_request(type, id) do
    url = Application.get_env(:bob, :master_url) <> "/queue/#{type}"
    secret = Application.get_env(:bob, :agent_secret)

    opts = [:with_body]
    headers = [{"authorization", secret}, {"content-type", "application/vnd.bob+erlang"}]
    body = Bob.Plug.ErlangFormat.encode_to_iodata!(%{id: id})
    {:ok, 204, _headers, ""} = :hackney.request(:post, url, headers, body, opts)
    :ok
  end

  defp start_request([], _num) do
    %{}
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
