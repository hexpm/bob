defmodule Bob.Script do
  @kill_after "30s"

  def run(action, args, dir) do
    File.mkdir_p!(dir)

    {:ok, :ok} =
      File.open(Path.join(dir, "out.txt"), [:write, :delayed_write], fn log ->
        {time, result} = :timer.tc(fn -> run_script(action, args, dir, log) end)
        IO.write(log, "\nCOMPLETED #{time / 1_000_000}s\n")
        result
      end)
  end

  defp run_script(action, args, dir, log) do
    case exec(action, args, dir, log) do
      :ok ->
        :ok

      %Porcelain.Result{status: 0} ->
        :ok

      %Porcelain.Result{status: status} ->
        raise "#{inspect(action)} #{inspect(args)} #{inspect(dir)} returned: #{status}"
    end
  end

  defp exec({:cmd, cmd}, [], dir, log) do
    Porcelain.shell(timeout_shell(cmd), out: {:file, log}, err: :out, dir: dir, env: env())
  end

  defp exec({:script, script}, args, dir, log) do
    script = Path.expand(Path.join(script_dir(), script))
    {exe, exe_args} = timeout_exec(script, args)
    Porcelain.exec(exe, exe_args, out: {:file, log}, err: :out, dir: dir, env: env())
  end

  # Bound every job so one that hangs anywhere — a stuck `docker build`,
  # `docker push`, `wget`, etc. — is killed instead of pinning a build slot
  # forever. GNU timeout run without --foreground signals the whole process
  # group, so the script's children die with it; killing the `docker` client
  # also makes the daemon cancel the build. Mirrors the runner's per-task
  # backstop. When timeout is unavailable (non-Linux dev) the script runs
  # unwrapped.
  defp timeout_exec(script, args) do
    case timeout_cmd() do
      nil -> {script, args}
      cmd -> {cmd, ["--kill-after=#{@kill_after}", timeout(), script | args]}
    end
  end

  defp timeout_shell(cmd) do
    case timeout_cmd() do
      nil -> cmd
      bin -> "#{bin} --kill-after=#{@kill_after} #{timeout()} #{cmd}"
    end
  end

  defp timeout_cmd() do
    System.find_executable("timeout") || System.find_executable("gtimeout")
  end

  defp timeout() do
    Application.get_env(:bob, :script_timeout, "3h")
  end

  defp env() do
    [{"SCRIPT_DIR", script_dir()}]
  end

  defp script_dir() do
    Path.join(Application.app_dir(:bob, "priv"), "scripts")
  end
end
