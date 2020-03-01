defmodule Bob.Job.QueueChecker do
  def run([:master]) do
    local_queue()
  end

  def run([:agent]) do
    local_queue()
    remote_queue()
  end

  def equal?(_, _), do: true

  def similar?(_, _), do: true

  defp local_queue() do
    Enum.each(Application.get_env(:bob, :local_jobs), fn module ->
      case Bob.Queue.dequeue(module) do
        {:ok, args} -> Bob.Runner.run(module, args)
        :error -> :ok
      end
    end)
  end

  defp remote_queue() do
    Enum.each(job_request(), fn {module, args} ->
      Bob.Runner.run(module, args)
    end)
  end

  defp job_request() do
    url = Application.get_env(:bob, :master_url) <> "/dequeue"
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
