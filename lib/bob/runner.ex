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

  def run(key, args) do
    GenServer.call(__MODULE__, {:run, key, args})
  end

  def state() do
    GenServer.call(__MODULE__, :state)
  end

  def handle_call({:run, key, args}, _from, state) do
    state = start_job(nil, key, args, state)
    {:reply, :ok, state}
  end

  def handle_call(:state, _from, state) do
    {:reply, state, state}
  end

  def handle_info({ref, result}, state) when is_reference(ref) do
    {key, args, job_id} = Map.fetch!(state.tasks, ref)

    case result do
      :ok ->
        if job_id, do: Bob.RemoteQueue.success(job_id)

      {:error, exception, stacktrace} ->
        if job_id, do: Bob.RemoteQueue.failure(job_id)
        Logger.error("FAILED #{inspect(key)} #{inspect(args)}")
        Bob.log_error(exception, stacktrace)
    end

    state = update_in(state.tasks, &Map.delete(&1, ref))
    state = start_any_jobs(state)
    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, _pid, :normal}, state) do
    {:noreply, state}
  end

  def handle_info(:local_timeout, state) do
    state = start_jobs(state, &Bob.RemoteQueue.local_queue/2)
    Process.send_after(self(), :local_timeout, @local_timeout)
    {:noreply, state}
  end

  def handle_info(:remote_timeout, state) do
    state = start_jobs(state, &Bob.RemoteQueue.remote_queue/2)
    Process.send_after(self(), :remote_timeout, @remote_timeout)
    {:noreply, state}
  end

  # Hackney leaking messages
  def handle_info(_, state) do
    {:noreply, state}
  end

  defp run_task(key, args) do
    {time, _} = :timer.tc(fn -> run_task_fun(key, args) end)
    Logger.info("COMPLETED #{inspect(key)} #{inspect(args)} (#{time / 1_000_000}s)")
    :ok
  rescue
    exception ->
      {:error, exception, __STACKTRACE__}
  end

  defp run_task_fun({module, key}, args), do: apply(module, :run, [key | args])
  defp run_task_fun(module, args), do: apply(module, :run, args)

  defp apply_task({module, _key}, fun, args), do: apply(module, fun, args)
  defp apply_task(module, fun, args), do: apply(module, fun, args)

  defp start_any_jobs(state) do
    state
    |> start_jobs(&Bob.RemoteQueue.local_queue/2)
    |> start_jobs(&Bob.RemoteQueue.remote_queue/2)
  end

  defp start_jobs(state, fun) do
    fun.(Application.get_env(:bob, :parallel_jobs), current_weight(state))
    |> Enum.reduce(state, fn {id, module, args}, state ->
      start_job(id, module, args, state)
    end)
  end

  defp current_weight(state) do
    Enum.reduce(state.tasks, %{}, fn {_ref, {module, _args, _id}}, weights ->
      concurrency_key = apply_task(module, :concurrency, [])
      weight = apply_task(module, :weight, [])
      Map.update(weights, concurrency_key, weight, &(&1 + weight))
    end)
  end

  defp start_job(id, key, args, state) do
    Logger.info("STARTING #{inspect(key)} #{inspect(args)}")
    task = Task.Supervisor.async(Bob.Tasks, fn -> run_task(key, args) end)
    put_in(state.tasks[task.ref], {key, args, id})
  end

  defp new_state do
    %{tasks: %{}}
  end
end
