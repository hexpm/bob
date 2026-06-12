defmodule Bob.Store do
  @bucket "s3.hex.pm"

  def fetch_file(path) do
    %{body: body} = ExAws.S3.get_object(@bucket, path, []) |> ExAws.request!()
    body
  end

  def fetch_text(path) do
    case ExAws.S3.get_object(@bucket, path, []) |> ExAws.request() do
      {:ok, %{body: body}} -> body
      {:error, {:http_error, 404, _}} -> nil
    end
  end

  def put_file(path, body, opts \\ []) do
    ExAws.S3.put_object(@bucket, path, body, opts)
    |> ExAws.request!()
  end

  def list_files(prefix) do
    ExAws.S3.list_objects(@bucket, prefix: prefix)
    |> ExAws.stream!()
    |> Stream.map(&Map.get(&1, :key))
  end
end
