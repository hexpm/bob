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

  def add(module, args) do
    GenServer.call(__MODULE__, {:add, module, args})
  end

  def start(module) do
    GenServer.call(__MODULE__, {:start, module})
  end

  def success(id) do
    GenServer.call(__MODULE__, {:success, id})
  end

  def failure(id) do
    GenServer.call(__MODULE__, {:failure, id})
  end

  def state() do
    GenServer.call(__MODULE__, :state)
  end

  def handle_call({:add, module, args}, _from, state) do
    state =
      cond do
        already_queued?(module, args, state) ->
          Logger.info("ALREADY QUEUED #{inspect(module)} #{inspect(args)}")
          state

        already_running?(module, args, state) ->
          Logger.info("ALREADY RUNNING #{inspect(module)} #{inspect(args)}")
          state

        true ->
          Logger.info("QUEUED #{inspect(module)} #{inspect(args)}")
          update_in(state.queues[module], &((&1 || []) ++ [args]))
      end

    {:reply, :ok, state}
  end

  def handle_call({:start, module}, _from, state) do
    case Map.get(state.queues, module, []) do
      [] ->
        {:reply, :error, state}

      [args | rest_args] ->
        now = NaiveDateTime.utc_now()
        id = :erlang.unique_integer()
        state = put_in(state.running_ids[id], {module, args, now})
        state = put_in(state.queues[module], rest_args)
        {:reply, {:ok, {id, args}}, state}
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

  def handle_call(:state, _from, state) do
    {:reply, state, state}
  end

  def handle_info(:timeout, state) do
    Process.send_after(self(), :timeout, @timeout_timer * 1000)
    now = NaiveDateTime.utc_now()

    # Right now we just prune instead of retrying and adding back to the queue
    # under the assumption that a job will eventually be added back
    state =
      Enum.reduce(state.running, state, fn {id, {_module, _args, created}}, state ->
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

  defp already_queued?(module, args, state) do
    Map.get(state.queues, module, [])
    |> Enum.any?(&(&1 == args))
  end

  defp already_running?(module, args, state) do
    Enum.any?(state.running, fn {_id, {running_module, running_args, _created}} ->
      module == running_module and args == running_args
    end)
  end

  defp new_state do
    %{queues: %{}, running: %{}}
  end
end
