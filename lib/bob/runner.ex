defmodule Bob.Runner do
  use GenServer
  require Logger

  def start_link([]) do
    GenServer.start_link(__MODULE__, new_state(), name: __MODULE__)
  end

  def init(state) do
    {:ok, state}
  end

  def run(module, args, opts \\ []) do
    GenServer.call(__MODULE__, {:run, module, args, Keyword.get(opts, :log, true)})
  end

  def state() do
    GenServer.call(__MODULE__, :state)
  end

  def handle_call({:run, module, args, log?}, _from, state) do
    state =
      cond do
        already_running?(state.tasks, module, args) ->
          if log?, do: Logger.info("ALREADY RUNNING #{inspect(module)} #{inspect(args)}")
          state

        true ->
          if log?, do: Logger.info("STARTING #{inspect(module)} #{inspect(args)}")
          task = Task.Supervisor.async(Bob.Tasks, fn -> run_task(module, args, log?) end)
          state = put_in(state.running[module], true)
          put_in(state.tasks[task.ref], {module, args})
      end

    {:reply, :ok, state}
  end

  def handle_call(:state, _from, state) do
    {:reply, state, state}
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
    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, _pid, :normal}, state) do
    {:noreply, state}
  end

  defp run_task(module, args, log?) do
    {time, _} = :timer.tc(fn -> module.run(args) end)

    if log?,
      do: Logger.info("COMPLETED #{inspect(module)} #{inspect(args)} (#{time / 1_000_000}s)")

    :ok
  catch
    kind, error ->
      {:error, kind, error, __STACKTRACE__}
  end

  defp already_running?(tasks, module, args) do
    Enum.any?(tasks, fn {_ref, {run_module, run_args}} ->
      run_module == module and module.equal?(run_args, args)
    end)
  end

  defp new_state do
    %{tasks: %{}, running: %{}}
  end
end
