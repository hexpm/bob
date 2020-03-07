defmodule Bob.Runner do
  use GenServer
  require Logger

  @local_timeout 1_000
  @remote_timeout 60_000

  def start_link([]) do
    GenServer.start_link(__MODULE__, new_state(), name: __MODULE__)
  end

  def init(state) do
    if Application.get_env(:bob, :master?) do
      Process.send_after(self(), :local_timeout, 0)
    else
      Process.send_after(self(), :local_timeout, 0)
      Process.send_after(self(), :remote_timeout, 0)
    end

    {:ok, state}
  end

  def run(module, args) do
    GenServer.call(__MODULE__, {:run, module, args})
  end

  def state() do
    GenServer.call(__MODULE__, :state)
  end

  def handle_call({:run, module, args}, _from, state) do
    state = start_job(nil, module, args, state)
    {:reply, :ok, state}
  end

  def handle_call(:state, _from, state) do
    {:reply, state, state}
  end

  def handle_info({ref, result}, state) do
    {module, args, job_id} = Map.fetch!(state.tasks, ref)

    case result do
      :ok ->
        if job_id, do: Bob.RemoteQueue.success(job_id)

      {:error, kind, error, stacktrace} ->
        if job_id, do: Bob.RemoteQueue.failure(job_id)
        Logger.error("FAILED #{inspect(module)} #{inspect(args)}")
        Bob.log_error(kind, error, stacktrace)
    end

    state = update_in(state.tasks, &Map.delete(&1, ref))
    state = start_any_jobs(state)
    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, _pid, :normal}, state) do
    {:noreply, state}
  end

  def handle_info(:local_timeout, state) do
    state = start_jobs(state, &Bob.RemoteQueue.local_queue/1)
    Process.send_after(self(), :local_timeout, @local_timeout)
    {:noreply, state}
  end

  def handle_info(:remote_timeout, state) do
    state = start_jobs(state, &Bob.RemoteQueue.remote_queue/1)
    Process.send_after(self(), :remote_timeout, @remote_timeout)
    {:noreply, state}
  end

  # Hackney leaking messages
  def handle_info(_, state) do
    {:noreply, state}
  end

  defp run_task(module, args) do
    {time, _} = :timer.tc(fn -> module.run(args) end)
    Logger.info("COMPLETED #{inspect(module)} #{inspect(args)} (#{time / 1_000_000}s)")
    :ok
  catch
    kind, error ->
      {:error, kind, error, __STACKTRACE__}
  end

  defp start_any_jobs(state) do
    state
    |> start_jobs(&Bob.RemoteQueue.local_queue/1)
    |> start_jobs(&Bob.RemoteQueue.remote_queue/1)
  end

  defp start_jobs(state, fun) do
    max(Application.get_env(:bob, :parallel_jobs) - map_size(state.tasks), 0)
    |> fun.()
    |> Enum.reduce(state, fn {id, module, args}, state ->
      start_job(id, module, args, state)
    end)
  end

  defp start_job(id, module, args, state) do
    Logger.info("STARTING #{inspect(module)} #{inspect(args)}")
    task = Task.Supervisor.async(Bob.Tasks, fn -> run_task(module, args) end)
    put_in(state.tasks[task.ref], {module, args, id})
  end

  defp new_state do
    %{tasks: %{}}
  end
end
