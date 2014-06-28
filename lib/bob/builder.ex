defmodule Bob.Builder do
  def build(name, ref, dir) do
    build_dir = Path.join(dir, "clone")

    repos = Application.get_env(:bob, :repos)
    repo  = repos[name]

    unless repo do
      raise "no configured repo with name #{name}"
    end

    {:ok, time} = File.open(Path.join(dir, "log.txt"), [:write, :delayed_write], fn log ->
      {time, _} = :timer.tc(fn ->
        clone(repo.git_url, ref, dir, log)
        run_build(repo.build, build_dir, log)
        zip(repo.zip, ref, build_dir, log)
      end)

      time = time / 1_000_000
      IO.write(log, "Build time: #{time}s")
      time
    end)

    time
  end

  def temp_dir do
    random =
      :erlang.now
      |> :erlang.term_to_binary
      |> hash()
      |> Base.encode16(case: :lower)

    path = Path.join("tmp", random)
    File.rm_rf!(path)
    File.mkdir_p!(path)

    path
  end

  defp clone(url, ref, dir, log) do
    cmd = "git clone #{url} clone -b #{ref} --depth 1 --single-branch"
    command(cmd, dir, log)
  end

  defp run_build(commands, dir, log) do
    Enum.each(commands, fn cmd ->
      command(cmd, dir, log)
    end)
  end

  defp zip(include, ref, dir, log) do
    zip = Path.join("..", "#{ref}.zip")
    cmd = "zip -9 -r #{zip} " <> Enum.join(include, " ")
    command(cmd, dir, log)
  end

  defp command(command, dir, log) do
    IO.write(log, "$ #{command}\n")

    %Porcelain.Result{status: status} =
      Porcelain.shell(command, out: {:file, log}, err: :out, dir: dir)

    IO.write(log, "\n")

    unless status == 0 do
      raise "`#{command}` returned: #{status}"
    end
  end

  defp hash(binary) do
    :crypto.hash(:md5, binary)
  end
end
