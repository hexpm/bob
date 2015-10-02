defmodule Bob.Builder do
  def build(repo, ref, jobs, dir) do
    name      = repo.name
    build_dir = Path.join(dir, name)
    preconfig = preconfig(ref)

    task(name, ref, dir, "clone", fn log ->
      clone(repo.git_url, ref, dir, log)
    end)

    if :build in jobs do
      task(name, ref, dir, "build", fn log ->
        run_build(repo.build, dir, preconfig, log)
      end)
    end

    if :zip in jobs do
      task(name, ref, dir, "zip", fn log ->
        zip(repo.zip, dir, log)
      end)

      task(name, ref, dir, "upload", fn _ ->
        upload(name, ref, build_dir)
      end)
    end

    if :docs in jobs do
      task(name, ref, dir, "docs", fn log ->
        docs(repo.docs, dir, log)
      end)
    end
  end

  defp preconfig(ref) do
    path = "/home/ericmj/.erln8.d/otps/#{erlang_version(ref)}"
    "#{path}:#{System.get_env("PATH") || ""}"
  end

  defp erlang_version("v1.0"), do: "17"
  defp erlang_version("v1.1"), do: "17"
  defp erlang_version("v" <> version) do
    if Version.compare(version, "1.2.0") == :lt,
        do: "17",
      else: "18"
  end
  defp erlang_version(_version), do: "18"

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
      :erlang.monotonic_time
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
    command(cmd, dir, nil, log)
  end

  defp run_build(commands, dir, preconfig, log) do
    Enum.each(commands, fn cmd ->
      command(cmd, dir, preconfig, log)
    end)
  end

  defp zip(commands, dir, log) do
    Enum.each(commands, fn cmd ->
      command(cmd, dir, nil, log)
    end)
  end

  defp upload(name, ref, dir) do
    blob = File.read!(Path.join(dir, "build.zip"))
    Bob.S3.upload(Bob.upload_path(name, ref), blob)
  end

  defp docs(commands, dir, log) do
    Enum.each(commands, fn cmd ->
      command(cmd, dir, nil, log)
    end)
  end

  defp command(command, dir, preconfig, log) do
    env = []
    if preconfig do
      env = [PATH: preconfig]
    end

    IO.write(log, "$ #{command}\n")

    %Porcelain.Result{status: status} =
      Porcelain.shell(command, out: {:file, log}, err: :out, dir: dir, env: env)

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
