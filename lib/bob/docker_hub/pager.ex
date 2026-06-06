defmodule Bob.DockerHub.Pager do
  use GenServer

  alias Bob.DockerHub.RateLimiter

  @concurrency 50
  @timeout 60 * 60 * 1000

  def start_link(url, on_page) do
    GenServer.start_link(__MODULE__, {url, on_page})
  end

  def wait(server) do
    GenServer.call(server, :wait, @timeout)
  end

  def init({url, on_page}) do
    {:ok,
     next_request(%{
       url: url,
       on_page: on_page,
       page: 1,
       tasks: MapSet.new(),
       reply: nil,
       error: nil
     })}
  end

  def handle_call(:wait, from, state) do
    cond do
      state.error ->
        {:stop, :normal, {:error, state.error}, state}

      MapSet.size(state.tasks) == 0 ->
        {:stop, :normal, :ok, state}

      true ->
        {:noreply, %{state | reply: from}}
    end
  end

  def handle_info({ref, {:ok, tags}}, state) do
    state.on_page.(tags)
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
        GenServer.reply(state.reply, :ok)
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

          RateLimiter.acquire()

          result =
            Bob.HTTP.retry("DockerHub #{url}", fn ->
              :hackney.request(:get, url, headers, "", opts)
            end)

          case result do
            {:ok, 200, headers, body} ->
              RateLimiter.observe(headers)
              decoded = JSON.decode!(body)
              {:ok, Enum.flat_map(decoded["results"], &List.wrap(Bob.DockerHub.parse(&1)))}

            {:ok, 404, headers, _body} ->
              RateLimiter.observe(headers)
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
