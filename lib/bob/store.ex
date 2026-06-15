defmodule Bob.Store do
  @bucket "s3.hex.pm"

  @doc """
  Signs `content` with the PEM private key at `pem_path` using
  `openssl dgst -sha512 -sign` and returns the base64-encoded signature, or
  `nil` when `pem_path` is `nil` (key not configured).
  """
  def sign_content(nil, _content), do: nil

  def sign_content(pem_path, content) do
    # Write content to a temp file so openssl can read from stdin cleanly for
    # arbitrary binary/text payloads.
    tmp = Path.join(System.tmp_dir!(), "bob_sign_#{System.unique_integer([:positive])}.tmp")

    try do
      File.write!(tmp, content)

      case System.cmd("openssl", ["dgst", "-sha512", "-sign", pem_path, tmp],
             stderr_to_stdout: false
           ) do
        {sig_binary, 0} -> Base.encode64(sig_binary)
        {_output, code} -> raise "openssl dgst exited with #{code}"
      end
    after
      File.rm(tmp)
    end
  end

  # TODO: Use S3 object metadata
  def fetch_built_refs(build_path) do
    path = Path.join(build_path, "builds.txt")

    case ExAws.S3.get_object(@bucket, path, []) |> ExAws.request() do
      {:ok, %{body: body}} ->
        body
        |> String.split("\n", trim: true)
        |> Map.new(&line_to_ref/1)

      {:error, {:http_error, 404, _}} ->
        %{}
    end
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

  defp line_to_ref(line) do
    destructure [ref_name, ref], String.split(line, " ", trim: true)
    {ref_name, ref}
  end
end
