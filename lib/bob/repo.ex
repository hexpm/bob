defmodule Bob.Repo do
  @bucket "s3.hex.pm"

  # TODO: Use S3 object metadata
  def fetch_built_refs(build_path) do
    key = Path.join(build_path, "builds.txt")

    {:ok, %{body: body}} = ExAws.S3.get_object(@bucket, key, []) |> ExAws.request()

    String.split(body, "\n", trim: true)
    |> Map.new(&line_to_ref/1)
  end

  defp line_to_ref(line) do
    destructure [ref_name, ref], String.split(line, " ", trim: true)
    {ref_name, ref}
  end
end
