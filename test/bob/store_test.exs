defmodule Bob.StoreTest do
  use ExUnit.Case

  alias Bob.Store

  setup do
    Bob.FakeHttpClient.reset()
    :ok
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
