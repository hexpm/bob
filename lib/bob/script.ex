defmodule Bob.Script do
  def run(action, args, dir) do
    {:ok, :ok} =
      File.open(Path.join(dir, "out.txt"), [:write, :delayed_write], fn log ->
        run_script(action, args, dir, log)
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
    Porcelain.shell(cmd, out: {:file, log}, err: :out, dir: dir, env: env())
  end

  defp exec({:script, script}, args, dir, log) do
    Path.join(script_dir(), script)
    |> Path.expand()
    |> Porcelain.exec(args, out: {:file, log}, err: :out, dir: dir, env: env())
  end

  defp env() do
    [{"SCRIPT_DIR", script_dir()}]
  end

  defp script_dir() do
    Path.join(Application.app_dir(:bob, "priv"), "scripts")
  end
end
