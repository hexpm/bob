defmodule Bob.Queue do
  use GenServer

  def start_link do
    GenServer.start_link(__MODULE__, new_state(), name: __MODULE__)
  end

  def run(repo, type, action, args, dir) do
    GenServer.call(__MODULE__, {:run, repo, type, action, args, dir})
  end

  def handle_call({:run, repo, type, action, args, dir}, _from, state) do
    state = update_in(state.queue, &:queue.in({repo, type, action, args, dir}, &1))
    state = dequeue(state)

    {:reply, :ok, state}
  end

  def handle_info(msg, state) do
    task =
      case Task.find(Map.keys(state.tasks), msg) do
        {:ok, task} ->
          task
        {{:error, kind, error, stacktrace}, task} ->
          %{dir: dir, name: name, type: type, action: action, args: args} = Map.get(state.tasks, task)
          IO.puts "FAILED #{name} #{type} #{inspect action} #{inspect(args)} (#{dir})"
          Bob.log_error(kind, error, stacktrace)
          task
      end

    clean_temp_dirs()

    state = %{state | building: false}
    state = update_in(state.tasks, &Map.delete(&1, task))
    state = dequeue(state)
    {:noreply, state}
  end

  defp dequeue(%{building: true} = state) do
    state
  end

  defp dequeue(state) do
    case :queue.out(state.queue) do
      {{:value, {name, type, action, args, dir}}, queue} ->
        temp_dir = temp_dir(dir, {name, type})
        now      = :calendar.local_time
        IO.puts "BUILDING #{name} #{type} #{inspect action} #{inspect(args)} (#{temp_dir}) (#{Bob.format_datetime(now)})"

        task = Task.Supervisor.async(Bob.Tasks, fn ->
          try do
            task(name, type, action, args, temp_dir)
            :ok
          catch
            kind, error ->
              {:error, kind, error, System.stacktrace}
          end
        end)

        map = %{dir: temp_dir, name: name, type: type, action: action, args: args}
        state = %{state | building: true}
        state = put_in(state.tasks[task], map)
        put_in(state.queue, queue)
      {:empty, _queue} ->
        state
    end
  end

  defp task(name, type, actions, args, dir) do
    {:ok, time} = File.open(Path.join(dir, "out.txt"), [:write, :delayed_write], fn log ->
      {time, _} = :timer.tc(fn ->
        Enum.each(actions, &run_task(&1, args, dir, log))
      end)
      time
    end)

    IO.puts "COMPLETED #{name} #{type} #{inspect actions} #{inspect(args)} (#{dir}) (#{time / 1_000_000}s)"
  end

  defp run_task(action, args, dir, log) do
    %Porcelain.Result{status: status} =
      case action do
        {:cmd, cmd} ->
          Porcelain.shell(cmd, out: {:file, log}, err: :out, dir: dir)
        {:script, script} ->
          Path.join("scripts", script)
          |> Path.expand
          |> Porcelain.exec(args, out: {:file, log}, err: :out, dir: dir)
      end

    unless status == 0 do
      raise "#{inspect action} #{inspect args} returned: #{status}"
    end
  end

  defp clean_temp_dirs do
    Path.wildcard("tmp/*")
    |> Enum.sort_by(&(File.stat!(&1).mtime), &>=/2)
    |> Enum.drop(10)
    |> Enum.each(&File.rm_rf!/1)
  end

  defp temp_dir(:persist, {name, type}) do
    path = Path.join("persist", "#{name}-#{type}")
    File.mkdir_p!(path)

    path
  end

  defp temp_dir(:temp, _name_type) do
    random =
      :crypto.strong_rand_bytes(16)
      |> Base.encode16(case: :lower)

    path = Path.join("tmp", random)
    File.rm_rf!(path)
    File.mkdir_p!(path)

    path
  end

  defp new_state do
    %{tasks: %{}, queue: :queue.new, building: false}
  end
end
