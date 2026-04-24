defmodule Bob.RepoTest do
  use ExUnit.Case

  alias Bob.Repo

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

      assert Repo.fetch_built_refs("builds/otp/amd64/ubuntu-24.04") == %{
               "OTP-26.2" => "abc123",
               "OTP-27.0" => "def456"
             }
    end

    test "returns an empty map when builds.txt does not exist yet" do
      assert Repo.fetch_built_refs("builds/otp/amd64/ubuntu-26.04") == %{}
    end

    test "returns an empty map when builds.txt is empty" do
      Bob.FakeHttpClient.stub(
        :get,
        "https://s3.amazonaws.com/s3.hex.pm/builds/otp/amd64/ubuntu-24.04/builds.txt",
        200,
        ""
      )

      assert Repo.fetch_built_refs("builds/otp/amd64/ubuntu-24.04") == %{}
    end
  end
end
