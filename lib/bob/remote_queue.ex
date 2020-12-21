defmodule Bob.RemoteQueue do
  def add(module, args) do
    request("/queue/add", %{module: module, args: args})
  end

  def docker_add(repo, tag, archs) do
    request("/docker/add", %{repo: repo, tag: tag, archs: archs})
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

  def local_queue(num) when num > 0 do
    Application.get_env(:bob, :local_jobs)
    |> prioritize()
    |> start_jobs(num)
    |> Enum.map(fn {id, module, args} -> {{:local, id}, module, args} end)
  end

  def local_queue(_num) do
    []
  end

  def remote_queue(num) when num > 0 do
    Application.get_env(:bob, :remote_jobs)
    |> start_request(num)
    |> Enum.map(fn {id, module, args} -> {{:remote, id}, module, args} end)
  end

  def remote_queue(_num) do
    []
  end

  def prioritize(jobs) do
    jobs
    |> Enum.group_by(&apply_job(&1, :priority, []), & &1)
    |> Enum.sort_by(fn {priority, _jobs} -> priority end)
    |> Enum.map(fn {priority, jobs} -> {priority, Enum.shuffle(jobs)} end)
  end

  # Don't do lower priority jobs if there is still higher priority jobs in queue.
  # This would ensure lower priority jobs with lower weight cannot race ahead
  # higher priority jobs with higher weight.
  def start_jobs(modules, num) do
    {started_jobs, _num} =
      Enum.flat_map_reduce(modules, num, fn
        {_priority, _modules}, 0 ->
          {:halt, 0}

        {_priority, jobs}, num ->
          Enum.flat_map_reduce(Stream.cycle(jobs ++ [:end]), {num, false}, fn
            _module, {0, _started?} ->
              {:halt, 0}

            :end, {num, true} ->
              {[], {num, false}}

            :end, {num, false} ->
              {:halt, num}

            module, {num, started?} ->
              new_num = num - apply_job(module, :weight, [])

              if new_num >= 0 do
                case Bob.Queue.start(module) do
                  {:ok, {id, args}} -> {[{id, module, args}], {new_num, true}}
                  :error -> {[], {num, started?}}
                end
              else
                {[], {num, started?}}
              end
          end)
      end)

    started_jobs
  end

  defp apply_job({module, _key}, fun, args), do: apply(module, fun, args)
  defp apply_job(module, fun, args), do: apply(module, fun, args)

  defp done_request(type, id) do
    request("/queue/#{type}", %{id: id})
    :ok
  end

  defp start_request([], _num) do
    %{}
  end

  defp start_request(remote_jobs, num) do
    {:ok, %{jobs: jobs}} = request("/queue/start", %{jobs: remote_jobs, num: num})
    jobs
  end

  defp request(url, body) do
    url = Application.get_env(:bob, :master_url) <> url
    secret = Application.get_env(:bob, :agent_secret)

    opts = [:with_body]
    headers = [{"authorization", secret}, {"content-type", "application/vnd.bob+erlang"}]
    body = Bob.Plug.ErlangFormat.encode_to_iodata!(body)

    case Bob.HTTP.retry("BobMaster", fn -> :hackney.request(:post, url, headers, body, opts) end) do
      {:ok, 200, _headers, body} ->
        {:ok, body} = Bob.Plug.ErlangFormat.decode(body)
        {:ok, body}

      {:ok, 204, _headers, ""} ->
        {:ok, nil}
    end
  end
end
