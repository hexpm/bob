defmodule Bob.Queue do
  use GenServer
  require Logger

  @timeout_timer 60
  @timeout 60 * 60

  def start_link([]) do
    GenServer.start_link(__MODULE__, new_state(), name: __MODULE__)
  end

  def init(state) do
    Process.send_after(self(), :timeout, @timeout_timer * 1000)
    {:ok, state}
  end

  def add(key, args) do
    GenServer.call(__MODULE__, {:add, key, args})
  end

  def start(key) do
    GenServer.call(__MODULE__, {:start, key})
  end

  def success(id) do
    GenServer.call(__MODULE__, {:success, id})
  end

  def failure(id) do
    GenServer.call(__MODULE__, {:failure, id})
  end

  def reset() do
    GenServer.call(__MODULE__, :reset)
  end

  def state() do
    GenServer.call(__MODULE__, :state)
  end

  def queue_sizes() do
    GenServer.call(__MODULE__, :queue_sizes)
  end

  def handle_call({:add, key, args}, _from, state) do
    state =
      cond do
        already_running?(key, args, state) ->
          state

        already_queued?(key, args, state) ->
          state

        true ->
          Logger.info("QUEUED #{inspect(key)} #{inspect(args)}")
          state = update_in(state.queue_sets[key], &MapSet.put(&1 || MapSet.new(), args))
          update_in(state.queues[key], &:queue.in(args, &1 || :queue.new()))
      end

    {:reply, :ok, state}
  end

  def handle_call({:start, key}, _from, state) do
    queue = Map.get(state.queues, key, :queue.new())

    case :queue.out(queue) do
      {{:value, args}, queue} ->
        now = NaiveDateTime.utc_now()
        id = :erlang.unique_integer()

        state = put_in(state.running[id], {key, args, now})
        state = put_in(state.queues[key], queue)
        state = update_in(state.queue_sets[key], &MapSet.delete(&1, args))
        {:reply, {:ok, {id, args}}, state}

      {:empty, _queue} ->
        {:reply, :error, state}
    end
  end

  def handle_call({:success, id}, _from, state) do
    {:reply, :ok, remove_job(id, state)}
  end

  def handle_call({:failure, id}, _from, state) do
    # Right now we just delete the job instead of retrying
    # under the assumption that a job will eventually be added back
    # Because of this the behaviour is the same as the success case
    {:reply, :ok, remove_job(id, state)}
  end

  def handle_call(:reset, _from, _state) do
    {:reply, :ok, new_state()}
  end

  def handle_call(:state, _from, state) do
    {:reply, state, state}
  end

  def handle_call(:queue_sizes, _from, state) do
    sizes = Enum.map(state.queue_sets, fn {key, set} -> {key, MapSet.size(set)} end)
    {:reply, sizes, state}
  end

  def handle_info(:timeout, state) do
    Process.send_after(self(), :timeout, @timeout_timer * 1000)
    now = NaiveDateTime.utc_now()

    # Right now we just prune instead of retrying and adding back to the queue
    # under the assumption that a job will eventually be added back
    state =
      Enum.reduce(state.running, state, fn {id, {_key, _args, created}}, state ->
        if NaiveDateTime.diff(now, created) > @timeout do
          remove_job(id, state)
        else
          state
        end
      end)

    {:noreply, state}
  end

  defp remove_job(id, state) do
    update_in(state.running, &Map.delete(&1, id))
  end

  defp already_queued?(key, args, state) do
    args in Map.get(state.queue_sets, key, MapSet.new())
  end

  defp already_running?(key, args, state) do
    Enum.any?(state.running, fn {_id, {running_key, running_args, _created}} ->
      key == running_key and args == running_args
    end)
  end

  defp new_state do
    %{queues: %{}, running: %{}, queue_sets: %{}}
  end
end
