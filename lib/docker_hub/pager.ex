defmodule Bob.DockerHub.Pager do
  use GenServer

  @concurrency 10
  @timeout 15 * 60_000

  def start_link(url) do
    GenServer.start_link(__MODULE__, url)
  end

  def wait(server) do
    GenServer.call(server, :wait, @timeout)
  end

  def init(url) do
    {:ok, next_request(%{url: url, page: 1, tasks: MapSet.new(), results: [], reply: nil})}
  end

  def handle_call(:wait, from, state) do
    if MapSet.size(state.tasks) == 0 do
      {:stop, :normal, Enum.concat(state.results), state}
    else
      state = %{state | reply: from}
      {:noreply, state}
    end
  end

  def handle_info({ref, {:ok, result}}, state) do
    state = %{state | tasks: MapSet.delete(state.tasks, ref), results: [result | state.results]}
    {:noreply, next_request(state)}
  end

  def handle_info({ref, :done}, state) do
    state = %{state | tasks: MapSet.delete(state.tasks, ref)}

    if MapSet.size(state.tasks) == 0 do
      GenServer.reply(state.reply, Enum.concat(state.results))
      {:stop, :normal, state}
    else
      {:noreply, state}
    end
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    {:noreply, state}
  end

  defp next_request(state) do
    if MapSet.size(state.tasks) < @concurrency do
      task =
        Task.async(fn ->
          url = String.replace(state.url, "${page}", Integer.to_string(state.page))
          headers = Bob.DockerHub.headers()
          opts = [:with_body, recv_timeout: 10_000]

          {:ok, 200, _headers, body} =
            Bob.HTTP.retry("DockerHub #{url}", fn ->
              :hackney.request(:get, url, headers, "", opts)
            end)

          body = Jason.decode!(body)

          if body["count"] == 0 do
            :done
          else
            {:ok, Enum.flat_map(body["results"], &List.wrap(Bob.DockerHub.parse(&1)))}
          end
        end)

      state = %{state | page: state.page + 1, tasks: MapSet.put(state.tasks, task.ref)}
      next_request(state)
    else
      state
    end
  end
end
