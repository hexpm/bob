defmodule Bob.DockerHub.Pager do
  use GenServer

  @concurrency 20
  @timeout 60 * 60 * 1000

  def start_link(url) do
    GenServer.start_link(__MODULE__, {url, nil})
  end

  def start_link(url, on_result) do
    GenServer.start_link(__MODULE__, {url, on_result})
  end

  def wait(server) do
    GenServer.call(server, :wait, @timeout)
  end

  def init({url, on_result}) do
    {:ok,
     next_request(%{
       url: url,
       on_result: on_result,
       page: 1,
       tasks: MapSet.new(),
       results: [],
       reply: nil,
       error: nil
     })}
  end

  def handle_call(:wait, from, state) do
    cond do
      state.error ->
        {:stop, :normal, {:error, state.error}, state}

      MapSet.size(state.tasks) == 0 ->
        result = if state.on_result, do: :ok, else: Enum.concat(state.results)
        {:stop, :normal, result, state}

      true ->
        {:noreply, %{state | reply: from}}
    end
  end

  def handle_info({ref, {:ok, result}}, state) do
    state =
      if state.on_result do
        state.on_result.(result)
        state
      else
        %{state | results: [result | state.results]}
      end

    state = %{state | tasks: MapSet.delete(state.tasks, ref)}
    {:noreply, next_request(state)}
  end

  def handle_info({ref, {:error, reason}}, state) do
    state = %{state | tasks: MapSet.delete(state.tasks, ref), error: reason}

    if state.reply do
      GenServer.reply(state.reply, {:error, reason})
      {:stop, :normal, state}
    else
      {:noreply, state}
    end
  end

  def handle_info({ref, :done}, state) do
    state = %{state | tasks: MapSet.delete(state.tasks, ref)}

    cond do
      MapSet.size(state.tasks) > 0 ->
        {:noreply, state}

      state.reply ->
        result = if state.on_result, do: :ok, else: Enum.concat(state.results)
        GenServer.reply(state.reply, result)
        {:stop, :normal, state}

      true ->
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
          opts = [:with_body, recv_timeout: 20_000]

          result =
            Bob.HTTP.retry("DockerHub #{url}", fn ->
              :hackney.request(:get, url, headers, "", opts)
            end)

          case result do
            {:ok, 200, _headers, body} ->
              decoded = JSON.decode!(body)
              {:ok, Enum.flat_map(decoded["results"], &List.wrap(Bob.DockerHub.parse(&1)))}

            {:ok, 404, _headers, _body} ->
              :done

            other ->
              {:error, other}
          end
        end)

      state = %{state | page: state.page + 1, tasks: MapSet.put(state.tasks, task.ref)}
      next_request(state)
    else
      state
    end
  end
end
