defmodule Bob.ArtifactsTest do
  use Bob.DataCase

  alias Bob.Artifacts.Artifact

  describe "Artifact.changeset/2" do
    test "casts a posted artifact, parsing the ISO8601 date" do
      changeset =
        Artifact.changeset(%Artifact{}, %{
          kind: "otp",
          arch: "amd64",
          os: "ubuntu-24.04",
          name: "OTP-27.0",
          ref: "abc123",
          sha256: "deadbeef",
          built_at: "2026-01-02T03:04:05Z"
        })

      assert changeset.valid?
      assert changeset.changes.built_at == ~U[2026-01-02 03:04:05.000000Z]
    end

    test "requires every field" do
      refute Artifact.changeset(%Artifact{}, %{}).valid?
    end
  end
end
