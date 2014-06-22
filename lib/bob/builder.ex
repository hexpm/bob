defmodule Bob.Builder do
  def build(name, ref, dir) do
    build_dir = Path.join(dir, "clone")

    IO.puts "BUILDING #{name} #{ref} into #{dir}"

    repos = Application.get_env(:bob, :repos)
    repo  = repos[name]

    unless repo do
      raise "no configured repo with name #{name}"
    end

    {:ok, time} = File.open(Path.join(dir, "log.txt"), [:write, :delayed_write], fn log ->
      {time, _} = :timer.tc(fn ->
        clone(repo.git_url, ref, dir, log)
        run_build(repo.build, build_dir, log)
        zip(repo.zip, ref, build_dir, dir)
      end)

      time = time / 1_000_000
      IO.write(log, "Build time: #{time}s")
      time
    end)

    IO.puts "COMPLETED #{name} #{ref} in #{dir} (#{time}s)"
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

  defp zip(include, ref, build_dir, dir) do
    include = expand_paths(include, build_dir)
              |> Enum.map(&String.to_char_list/1)

    file = Path.join(dir, "#{ref}.zip")
           |> String.to_char_list

    build_dir = String.to_char_list(build_dir)

    {:ok, _} = :zip.create(file, include, cwd: build_dir)
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

  defp expand_paths(paths, dir) do
    expand_dir = Path.expand(dir)

    paths
    |> Enum.map(&Path.join(dir, &1))
    |> Enum.flat_map(&Path.wildcard/1)
    |> Enum.flat_map(&dir_files/1)
    |> Enum.map(&Path.expand/1)
    |> Enum.filter(&File.regular?/1)
    |> Enum.uniq
    |> Enum.map(&Path.relative_to(&1, expand_dir))
  end

  defp dir_files(path) do
    if File.dir?(path) do
      Path.wildcard(Path.join(path, "**"))
    else
      [path]
    end
  end
end
