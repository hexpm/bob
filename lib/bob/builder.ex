defmodule Bob.Builder do
  def build(repo, ref, jobs, dir) do
    name = repo.name

    task(name, ref, dir, "clone", fn log ->
      clone(repo.git_url, ref, dir, log)
    end)

    if :build in jobs do
      task(name, ref, dir, "build", fn log ->
        run_build(repo.build, dir, log)
      end)
    end

    if :zip in jobs do
      task(name, ref, dir, "zip", fn log ->
        zip(repo.zip, ref, dir, log)
      end)

      task(name, ref, dir, "upload", fn _ ->
        upload(name, ref, dir)
      end)
    end

    if :docs in jobs do
      task(name, ref, dir, "docs", fn log ->
        docs(repo.docs, dir, log)
      end)
    end
  end

  defp task(name, ref, dir, task, fun) do
    {:ok, _} = File.open(Path.join(dir, "#{task}.txt"), [:write, :delayed_write], fn log ->
      {time, _} = :timer.tc(fn ->
        fun.(log)
      end)

      output(name, ref, dir, log, time, "#{task} DONE")
    end)
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
    cmd = "git clone #{url} -b #{ref} --depth 1 --single-branch"
    command(cmd, dir, log)
  end

  defp run_build(commands, dir, log) do
    Enum.each(commands, fn cmd ->
      command(cmd, dir, log)
    end)
  end

  defp zip(commands, ref, dir, log) do
    Enum.each(commands, fn cmd ->
      command(cmd, dir, log)
    end)
    :file.rename(Path.join(dir, "build.zip"), Path.join([dir, "..", "#{ref}.zip"]))
  end

  defp upload(name, ref, dir) do
    blob = File.read!(Path.join(dir, "#{ref}.zip"))
    Bob.S3.upload(Bob.upload_path(name, ref), blob)
  end

  defp docs(commands, dir, log) do
    Enum.each(commands, fn cmd ->
      command(cmd, dir, log)
    end)
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

  defp output(name, ref, dir, log, time, message) do
    time = time / 1_000_000
    IO.write(log, "\nCOMPLETED IN #{time}s")
    IO.puts "#{message} #{name} #{ref} (#{dir}) (#{time}s)"
  end
end
