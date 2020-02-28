defmodule Bob.Repo do
  @bucket "s3.hex.pm"

  # TODO: Use S3 object metadata
  def fetch_built_refs(build_path) do
    Path.join(build_path, "builds.txt")
    |> fetch_file()
    |> String.split("\n", trim: true)
    |> Map.new(&line_to_ref/1)
  end

  def fetch_file(path) do
    %{body: body} = ExAws.S3.get_object(@bucket, path, []) |> ExAws.request!()
    body
  end

  def list_files(prefix) do
    ExAws.S3.list_objects(@bucket, prefix: prefix)
    |> ExAws.stream!()
    |> Stream.map(&Map.get(&1, :key))
  end

  defp line_to_ref(line) do
    destructure [ref_name, ref], String.split(line, " ", trim: true)
    {ref_name, ref}
  end
end
