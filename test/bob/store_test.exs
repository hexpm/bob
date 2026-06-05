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
end
