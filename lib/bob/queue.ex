defmodule Bob.Queue do
  use GenServer

  def start_link() do
    GenServer.start_link(__MODULE__, new_state(), name: __MODULE__)
  end

  def run(repo, type, action, args, dir) do
    GenServer.call(__MODULE__, {:run, repo, type, action, args, dir})
  end

  def handle_call({:run, repo, type, action, args, dir}, _from, state) do
    # TOOD: Better duplicate check for OTP builds since we include the sha with the branch name
    # in the arguments which means two quick commits to the same branch will trigger two builds
    # instead of only one
    action = {repo, type, action, args, dir}
    state =
      if :queue.member(action, state.queue) do
        IO.puts "DUPLICATE #{repo} #{type} #{inspect action} #{inspect(args)} (#{dir})"
        state
      else
        state = update_in(state.queue, &:queue.in(action, &1))
        dequeue(state)
      end

    {:reply, :ok, state}
  end

  def handle_info({ref, result}, state) do
    case result do
      :ok ->
        :ok
      {:error, kind, error, stacktrace} ->
        %{dir: dir, name: name, type: type, action: action, args: args} = Map.get(state.tasks, ref)
        IO.puts "FAILED #{name} #{type} #{inspect action} #{inspect(args)} (#{dir})"
        Bob.log_error(kind, error, stacktrace)
    end

    clean_temp_dirs()

    state = %{state | building: false}
    state = update_in(state.tasks, &Map.delete(&1, ref))
    state = dequeue(state)
    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, _pid, :normal}, state) do
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
        state = put_in(state.tasks[task.ref], map)
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
    case run_action(action, args, dir, log) do
      :ok ->
        :ok
      %Porcelain.Result{status: 0} ->
        :ok
      %Porcelain.Result{status: status} ->
        raise "#{inspect action} #{inspect args} returned: #{status}"
    end
  end

  defp run_action({:cmd, cmd}, [], dir, log) do
    Porcelain.shell(cmd, out: {:file, log}, err: :out, dir: dir)
  end

  defp run_action({:script, script}, args, dir, log) do
    Path.join("scripts", script)
    |> Path.expand
    |> Porcelain.exec(args, out: {:file, log}, err: :out, dir: dir)
  end

  defp run_action({:github, repo}, _args, _dir, _log) do
    Enum.each(Bob.GitHub.diff(repo), fn {ref_name, ref} ->
      repos = Application.get_env(:bob, :repos)
      repo_key = repos[repo]
      repo = Application.get_env(:bob, repo_key)
      action = repo[:github]

      Bob.Queue.run(repo_key, :github, action, [ref_name, ref], :temp)
    end)

    :ok
  end

  defp clean_temp_dirs() do
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
