defmodule Bob.Script do
  def run(action, args, dir) do
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
        raise "#{inspect(action)} #{inspect(args)} returned: #{status}"
    end
  end

  defp exec({:cmd, cmd}, [], dir, log) do
    Porcelain.shell(cmd, out: {:file, log}, err: :out, dir: dir)
  end

  defp exec({:script, script}, args, dir, log) do
    Path.join("scripts", script)
    |> Path.expand()
    |> Porcelain.exec(args, out: {:file, log}, err: :out, dir: dir)
  end
end
