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

  def local_queue(max_weight, weights) do
    Application.get_env(:bob, :local_jobs)
    |> prioritize()
    |> start_jobs(max_weight, weights)
    |> Enum.map(fn {id, module, args} -> {{:local, id}, module, args} end)
  end

  def remote_queue(max_weight, weights) do
    Application.get_env(:bob, :remote_jobs)
    |> start_request(max_weight, weights)
    |> Enum.map(fn {id, module, args} -> {{:remote, id}, module, args} end)
  end

  def prioritize(jobs) do
    jobs
    |> Enum.group_by(&apply_job(&1, :priority, []), & &1)
    |> Enum.sort_by(fn {priority, _jobs} -> priority end)
    |> Enum.flat_map(fn {_priority, jobs} -> Enum.shuffle(jobs) end)
  end

  # Don't do lower priority jobs if there is still higher priority jobs in queue.
  # This would ensure lower priority jobs with lower weight cannot race ahead
  # higher priority jobs with higher weight.
  def start_jobs(modules, max_weight, weights) do
    {started_jobs, _weights} =
      Enum.flat_map_reduce(Stream.cycle(modules ++ [:end]), {weights, false}, fn
        :end, {weights, true} ->
          {[], {weights, false}}

        :end, {weights, false} ->
          {:halt, weights}

        module, {weights, started?} ->
          concurrency_key = apply_job(module, :concurrency, [])

          new_weight = Map.get(weights, concurrency_key, 0) + apply_job(module, :weight, [])

          if new_weight <= max_weight do
            case Bob.Queue.start(module) do
              {:ok, {id, args}} ->
                weights = Map.put(weights, concurrency_key, new_weight)
                {[{id, module, args}], {weights, true}}

              :error ->
                {[], {weights, started?}}
            end
          else
            {[], {weights, started?}}
          end
      end)

    started_jobs
  end

  defp apply_job({module, _key}, fun, args), do: apply(module, fun, args)
  defp apply_job(module, fun, args), do: apply(module, fun, args)

  defp done_request(type, id) do
    request("/queue/#{type}", %{id: id})
    :ok
  end

  defp start_request([], _max_weight, _weights) do
    %{}
  end

  defp start_request(remote_jobs, max_weight, weights) do
    {:ok, %{jobs: jobs}} =
      request("/queue/start", %{jobs: remote_jobs, max_weight: max_weight, weights: weights})

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
