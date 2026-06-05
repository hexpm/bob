defmodule Bob.ArtifactsTest do
  use Bob.DataCase

  alias Bob.Artifacts
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

  describe "upsert/1" do
    test "inserts a new artifact" do
      Artifacts.upsert(attrs())
      assert [%Artifact{name: "OTP-27.0", ref: "abc123"}] = Repo.all(Artifact)
    end

    test "replaces ref/sha256/built_at on conflicting (kind, arch, os, name)" do
      Artifacts.upsert(attrs())

      Artifacts.upsert(%{
        attrs()
        | ref: "new999",
          sha256: "feed",
          built_at: "2026-02-02T02:02:02Z"
      })

      assert [%Artifact{ref: "new999", sha256: "feed", built_at: ~U[2026-02-02 02:02:02.000000Z]}] =
               Repo.all(Artifact)
    end
  end

  describe "builds_txt/2" do
    test "renders one line per artifact, sorted by name, second-precision date" do
      Artifacts.upsert(%{attrs() | name: "OTP-27.0", ref: "r27", sha256: "h27"})
      Artifacts.upsert(%{attrs() | name: "OTP-26.0", ref: "r26", sha256: "h26"})
      Artifacts.upsert(%{attrs() | name: "maint", ref: "rm", sha256: "hm"})

      assert Artifacts.builds_txt("amd64", "ubuntu-24.04") == """
             OTP-26.0 r26 2026-01-02T03:04:05Z h26
             OTP-27.0 r27 2026-01-02T03:04:05Z h27
             maint rm 2026-01-02T03:04:05Z hm
             """
    end

    test "scopes to the requested arch and os" do
      Artifacts.upsert(%{attrs() | arch: "amd64", os: "ubuntu-24.04", name: "OTP-27.0"})
      Artifacts.upsert(%{attrs() | arch: "arm64", os: "ubuntu-24.04", name: "OTP-27.0"})
      Artifacts.upsert(%{attrs() | arch: "amd64", os: "ubuntu-22.04", name: "OTP-27.0"})

      assert Artifacts.builds_txt("arm64", "ubuntu-24.04") =~ "OTP-27.0"

      assert Artifacts.builds_txt("amd64", "ubuntu-24.04")
             |> String.split("\n", trim: true)
             |> length() == 1
    end

    test "renders an empty string when there are no matching artifacts" do
      assert Artifacts.builds_txt("amd64", "ubuntu-24.04") == ""
    end
  end

  describe "generate_builds_txt/2" do
    test "uploads the rendered builds.txt to S3" do
      Bob.FakeHttpClient.reset()

      Bob.FakeHttpClient.stub(
        :put,
        "https://s3.amazonaws.com/s3.hex.pm/builds/otp/amd64/ubuntu-24.04/builds.txt",
        200,
        ""
      )

      Artifacts.upsert(attrs())

      assert "builds/otp/amd64/ubuntu-24.04/builds.txt" =
               Artifacts.generate_builds_txt("amd64", "ubuntu-24.04")
    end
  end

  describe "built_otp_refs/2" do
    test "returns a name => ref map scoped to arch/os" do
      Artifacts.upsert(%{attrs() | name: "OTP-27.0", ref: "r27"})
      Artifacts.upsert(%{attrs() | name: "OTP-26.0", ref: "r26"})
      Artifacts.upsert(%{attrs() | arch: "arm64", name: "OTP-27.0", ref: "other"})

      assert Artifacts.built_otp_refs("amd64", "ubuntu-24.04") == %{
               "OTP-27.0" => "r27",
               "OTP-26.0" => "r26"
             }
    end
  end

  describe "add/1" do
    test "upserts and regenerates builds.txt" do
      Bob.FakeHttpClient.reset()

      Bob.FakeHttpClient.stub(
        :put,
        "https://s3.amazonaws.com/s3.hex.pm/builds/otp/amd64/ubuntu-24.04/builds.txt",
        200,
        ""
      )

      assert Artifacts.add(attrs()) == :ok
      assert [%Artifact{name: "OTP-27.0"}] = Repo.all(Artifact)
    end
  end

  defp attrs() do
    %{
      kind: "otp",
      arch: "amd64",
      os: "ubuntu-24.04",
      name: "OTP-27.0",
      ref: "abc123",
      sha256: "deadbeef",
      built_at: "2026-01-02T03:04:05Z"
    }
  end
end
