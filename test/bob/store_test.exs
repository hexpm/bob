defmodule Bob.StoreTest do
  use ExUnit.Case

  alias Bob.Store

  setup do
    Bob.FakeHttpClient.reset()
    :ok
  end

  describe "fetch_built_refs/1" do
    test "parses lines into a ref_name => ref map" do
      body = """
      OTP-26.2 abc123 2026-01-01T00:00:00Z hash1
      OTP-27.0 def456 2026-02-01T00:00:00Z hash2
      """

      Bob.FakeHttpClient.stub(
        :get,
        "https://s3.amazonaws.com/s3.hex.pm/builds/otp/amd64/ubuntu-24.04/builds.txt",
        200,
        body
      )

      assert Store.fetch_built_refs("builds/otp/amd64/ubuntu-24.04") == %{
               "OTP-26.2" => "abc123",
               "OTP-27.0" => "def456"
             }
    end

    test "returns an empty map when builds.txt does not exist yet" do
      assert Store.fetch_built_refs("builds/otp/amd64/ubuntu-26.04") == %{}
    end

    test "returns an empty map when builds.txt is empty" do
      Bob.FakeHttpClient.stub(
        :get,
        "https://s3.amazonaws.com/s3.hex.pm/builds/otp/amd64/ubuntu-24.04/builds.txt",
        200,
        ""
      )

      assert Store.fetch_built_refs("builds/otp/amd64/ubuntu-24.04") == %{}
    end
  end

  describe "fetch_text/1" do
    test "returns the body for an existing object" do
      Bob.FakeHttpClient.reset()

      Bob.FakeHttpClient.stub(
        :get,
        "https://s3.amazonaws.com/s3.hex.pm/builds/otp/amd64/ubuntu-24.04/builds.txt",
        200,
        "OTP-27.0 abc 2026-01-02T03:04:05Z deadbeef\n"
      )

      assert Bob.Store.fetch_text("builds/otp/amd64/ubuntu-24.04/builds.txt") ==
               "OTP-27.0 abc 2026-01-02T03:04:05Z deadbeef\n"
    end

    test "returns nil when the object does not exist" do
      Bob.FakeHttpClient.reset()
      assert Bob.Store.fetch_text("builds/otp/amd64/ubuntu-24.04/builds.txt") == nil
    end
  end

  describe "put_file/3" do
    test "uploads the body to the bucket path" do
      Bob.FakeHttpClient.stub(
        :put,
        "https://s3.amazonaws.com/s3.hex.pm/builds/otp/amd64/ubuntu-24.04/builds.txt",
        200,
        ""
      )

      assert %{status_code: 200} =
               Store.put_file(
                 "builds/otp/amd64/ubuntu-24.04/builds.txt",
                 "OTP-27.0 abc 2026-01-01T00:00:00Z hash\n",
                 cache_control: "public,max-age=3600",
                 meta: [
                   {"surrogate-key", "builds"},
                   {"surrogate-control", "public,max-age=604800"}
                 ]
               )
    end
  end

  describe "sign_content/2" do
    test "returns nil when no key path is configured" do
      assert Store.sign_content(nil, "some content") == nil
    end

    test "returns a base64 signature for a valid PEM key" do
      pem_path = generate_test_key()

      signature = Store.sign_content(pem_path, "OTP-27.0 abc123 2026-01-01T00:00:00Z hash\n")

      assert is_binary(signature)
      assert {:ok, _} = Base.decode64(signature)
      assert byte_size(Base.decode64!(signature)) > 0
    end

    test "the signature verifies against the content using the matching public key" do
      pem_path = generate_test_key()
      pub_path = pem_path <> ".pub"

      # Export the public key once
      {pub_pem, 0} = System.cmd("openssl", ["rsa", "-pubout", "-in", pem_path])
      File.write!(pub_path, pub_pem)

      content = "OTP-27.0 abc123 2026-01-01T00:00:00Z hash\n"
      b64_sig = Store.sign_content(pem_path, content)
      sig_bytes = Base.decode64!(b64_sig)

      # Write sig bytes to a temp file for verification
      sig_path = pem_path <> ".sig"
      File.write!(sig_path, sig_bytes)

      content_path = pem_path <> ".content"
      File.write!(content_path, content)

      {_output, exit_code} =
        System.cmd(
          "openssl",
          ["dgst", "-sha512", "-verify", pub_path, "-signature", sig_path, content_path]
        )

      assert exit_code == 0
    end
  end

  # Generates a 2048-bit RSA key into a temp file and returns its path.
  # The key is created once per process lifetime; the file persists across tests
  # within the test run (harmless temp file, cleaned up by the OS).
  defp generate_test_key() do
    pem_path = Path.join(System.tmp_dir!(), "bob_test_key.pem")

    unless File.exists?(pem_path) do
      {_out, 0} = System.cmd("openssl", ["genrsa", "-out", pem_path, "2048"])
    end

    pem_path
  end
end
