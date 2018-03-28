defmodule Bob.Directory do
  @max_temp_dirs 100

  def new() do
    clean_temp_dirs()

    random =
      :crypto.strong_rand_bytes(16)
      |> Base.encode16(case: :lower)

    path = Path.join("tmp", random)
    File.rm_rf!(path)
    File.mkdir_p!(path)

    path
  end

  defp clean_temp_dirs() do
    Path.wildcard("tmp/*")
    |> Enum.sort_by(&File.stat!(&1).mtime, &>=/2)
    |> Enum.drop(@max_temp_dirs)
    |> Enum.each(&File.rm_rf!/1)
  end
end
