defmodule Bob.Job.OTPCheckerTest do
  use Bob.DataCase

  alias Bob.Job.OTPChecker
  alias Bob.Artifacts

  defp artifact(attrs) do
    Artifacts.upsert(
      Map.merge(
        %{
          kind: "otp",
          arch: "amd64",
          os: "ubuntu-24.04",
          sha256: "h",
          built_at: "2026-01-01T00:00:00Z"
        },
        attrs
      )
    )
  end

  describe "unbuilt/3" do
    test "drops refs whose stored artifact ref matches" do
      artifact(%{name: "OTP-27.0", ref: "abc"})

      refs = [{"OTP-27.0", "abc"}, {"OTP-26.0", "def"}]

      assert OTPChecker.unbuilt(refs, "amd64", "ubuntu-24.04") == [{"OTP-26.0", "def"}]
    end

    test "keeps a ref whose stored artifact ref differs (re-tagged)" do
      artifact(%{name: "OTP-27.0", ref: "old"})

      refs = [{"OTP-27.0", "new"}]

      assert OTPChecker.unbuilt(refs, "amd64", "ubuntu-24.04") == [{"OTP-27.0", "new"}]
    end

    test "scopes built state by arch and os" do
      artifact(%{name: "OTP-27.0", ref: "abc", arch: "amd64", os: "ubuntu-24.04"})

      refs = [{"OTP-27.0", "abc"}]

      assert OTPChecker.unbuilt(refs, "arm64", "ubuntu-24.04") == [{"OTP-27.0", "abc"}]
      assert OTPChecker.unbuilt(refs, "amd64", "ubuntu-26.04") == [{"OTP-27.0", "abc"}]
      assert OTPChecker.unbuilt(refs, "amd64", "ubuntu-24.04") == []
    end
  end
end
