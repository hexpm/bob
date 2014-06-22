defmodule Bob.Queue do
  use GenServer

  def start_link do
    GenServer.start_link(__MODULE__, new_state(), name: __MODULE__)
  end

  def build(repo, ref) do
    GenServer.call(__MODULE__, {:build, repo, ref})
  end

  def handle_call({:build, repo, ref}, _from, state) do
    temp_dir = Bob.Builder.temp_dir
    IO.puts "BUILDING #{repo} #{ref} (#{temp_dir})"

    task = Task.Supervisor.async(Bob.BuildSupervisor, fn ->
      try do
        task(repo, ref, temp_dir)
        :ok
      catch
        type, term ->
          {:error, type, term, System.stacktrace}
      end
    end)

    state = put_in(state.tasks[task], %{dir: temp_dir, repo: repo, ref: ref})
    {:reply, :ok, state}
  end

  def handle_info(msg, state) do
    task =
      case Task.find(Map.keys(state.tasks), msg) do
        {:ok, task} ->
          task
        {{:error, type, term, stacktrace}, task} ->
          %{dir: dir, repo: repo, ref: ref} = Map.get(state.tasks, task)
          IO.puts "FAILED #{repo} #{ref} (#{dir})"
          Bob.log_error(type, term, stacktrace)
          task
      end

    state = update_in(state.tasks, &Map.delete(&1, task))
    {:noreply, state}
  end

  defp task(repo, ref, dir) do
    time = Bob.Builder.build(repo, ref, dir)
    IO.puts "COMPLETED #{repo} #{ref} (#{dir}) (#{time}s)"

    upload(repo, ref, dir)
    IO.puts "UPLOADED #{repo} #{ref} (#{dir})"
  end

  defp upload(repo, ref, dir) do
    blob = File.read!(Path.join(dir, "#{ref}.zip"))
    Bob.S3.upload(Bob.upload_path(repo, ref), blob)
  end

  defp new_state do
    %{tasks: %{}}
  end
end
