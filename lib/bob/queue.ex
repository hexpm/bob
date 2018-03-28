defmodule Bob.Queue do
  use GenServer
  require Logger

  def start_link() do
    GenServer.start_link(__MODULE__, new_state(), name: __MODULE__)
  end

  def init(state) do
    {:ok, state}
  end

  def run(module, args) do
    GenServer.call(__MODULE__, {:run, module, args})
  end

  def handle_call({:run, module, args}, _from, state) do
    queue = Map.get(state.queue, module, [])
    duplicate? = Enum.any?(queue, &module.equal?(&1, args))

    state =
      if duplicate? do
        Logger.info("DUPLICATE #{inspect(module)} #{inspect(args)}")
        state
      else
        state = update_in(state.queue[module], &(&1 || [] ++ [args]))
        dequeue(state, module)
      end

    {:reply, :ok, state}
  end

  def handle_info({ref, result}, state) do
    {module, args} = Map.fetch!(state.tasks, ref)

    case result do
      :ok ->
        :ok

      {:error, kind, error, stacktrace} ->
        Logger.error("FAILED #{inspect(module)} #{inspect(args)}")
        Bob.log_error(kind, error, stacktrace)
    end

    state = update_in(state.running, &Map.delete(&1, module))
    state = update_in(state.tasks, &Map.delete(&1, ref))
    state = dequeue(state, module)
    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, _pid, :normal}, state) do
    {:noreply, state}
  end

  defp dequeue(state, module) do
    case state do
      %{running: %{^module => true}} -> state
      %{queue: %{^module => []}} -> state
      %{queue: %{^module => queue}} -> dequeue_task(state, module, queue)
    end
  end

  defp dequeue_task(state, module, [args | module_queue]) do
    Logger.info("STARTING #{inspect(module)} #{inspect(args)}")
    task = Task.Supervisor.async(Bob.Tasks, fn -> task_fun(module, args) end)

    state = put_in(state.running[module], true)
    state = put_in(state.tasks[task.ref], {module, args})
    put_in(state.queue[module], module_queue)
  end

  defp task_fun(module, args) do
    try do
      run_task(module, args)
      :ok
    catch
      kind, error ->
        {:error, kind, error, System.stacktrace()}
    end
  end

  defp run_task(module, args) do
    {time, _} = :timer.tc(fn -> module.run(args) end)
    IO.puts("COMPLETED #{inspect(module)} #{inspect(args)} (#{time / 1_000_000}s)")
  end

  defp new_state do
    %{tasks: %{}, queue: %{}, running: %{}}
  end
end
