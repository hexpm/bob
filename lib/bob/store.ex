defmodule Bob.Store do
  @bucket "s3.hex.pm"

  @doc """
  Signs `content` with the PEM private key at `pem_path` using
  `:public_key.sign/3` with SHA-512 and returns the base64-encoded signature, or
  `nil` when `pem_path` is `nil` (key not configured).
  """
  def sign_content(nil, _content), do: nil

  def sign_content(pem_path, content) do
    [entry] = pem_path |> File.read!() |> :public_key.pem_decode()
    private_key = :public_key.pem_entry_decode(entry)

    content
    |> :public_key.sign(:sha512, private_key)
    |> Base.encode64()
  end

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
