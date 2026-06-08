defmodule Bob.ArtifactsTest do
  use Bob.DataCase

  alias Bob.Artifacts
  alias Bob.Artifacts.{Artifact, BaseImageTag, DockerTag}

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

    test "requires every field but sha256" do
      refute Artifact.changeset(%Artifact{}, %{}).valid?
    end

    test "is valid without a sha256 (historical OTP build)" do
      changeset =
        Artifact.changeset(%Artifact{}, %{
          kind: "otp",
          arch: "amd64",
          os: "ubuntu-24.04",
          name: "OTP-27.0",
          ref: "abc123",
          built_at: "2026-01-02T03:04:05Z"
        })

      assert changeset.valid?
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

  describe "import_artifacts/1" do
    test "bulk-inserts rows and upserts on a conflicting (kind, arch, os, name)" do
      assert Artifacts.import_artifacts([
               row("OTP-27.0", "r27", "h27"),
               row("OTP-26.0", "r26", nil)
             ]) == :ok

      Artifacts.import_artifacts([row("OTP-27.0", "r27b", "h27b")])

      assert [
               %Artifact{name: "OTP-26.0", sha256: nil},
               %Artifact{name: "OTP-27.0", sha256: "h27b"}
             ] =
               Repo.all(from(a in Artifact, order_by: a.name))

      assert Artifacts.built_otp_refs("amd64", "ubuntu-24.04") == %{
               "OTP-27.0" => "r27b",
               "OTP-26.0" => "r26"
             }
    end

    test "returns :ok for an empty list" do
      assert Artifacts.import_artifacts([]) == :ok
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

    test "omits the checksum column for builds without a sha256" do
      Artifacts.upsert(%{attrs() | name: "OTP-27.0", ref: "r27", sha256: nil})
      Artifacts.upsert(%{attrs() | name: "OTP-28.0", ref: "r28", sha256: "h28"})

      assert Artifacts.builds_txt("amd64", "ubuntu-24.04") == """
             OTP-27.0 r27 2026-01-02T03:04:05Z
             OTP-28.0 r28 2026-01-02T03:04:05Z h28
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

  describe "add_docker_tag/3" do
    test "inserts a new docker tag row" do
      assert Artifacts.add_docker_tag("hexpm/erlang-amd64", "27.0-ubuntu-noble-20250101", [
               "amd64"
             ]) ==
               :ok

      assert Artifacts.docker_tags("hexpm/erlang-amd64") ==
               [{"27.0-ubuntu-noble-20250101", ["amd64"]}]
    end

    test "unions archs on conflicting (repo, tag)" do
      Artifacts.add_docker_tag("hexpm/erlang", "27.0-ubuntu-noble-20250101", ["amd64"])
      Artifacts.add_docker_tag("hexpm/erlang", "27.0-ubuntu-noble-20250101", ["arm64"])

      assert Artifacts.docker_tags("hexpm/erlang") ==
               [{"27.0-ubuntu-noble-20250101", ["amd64", "arm64"]}]
    end

    test "is idempotent for a repeated single-arch report" do
      Artifacts.add_docker_tag("hexpm/erlang-amd64", "27.0-ubuntu-noble-20250101", ["amd64"])
      Artifacts.add_docker_tag("hexpm/erlang-amd64", "27.0-ubuntu-noble-20250101", ["amd64"])

      assert Artifacts.docker_tags("hexpm/erlang-amd64") ==
               [{"27.0-ubuntu-noble-20250101", ["amd64"]}]
    end

    test "stamps inserted_at and updated_at, advancing only updated_at on conflict" do
      Artifacts.add_docker_tag("hexpm/erlang", "27.0-ubuntu-noble-20250101", ["amd64"])
      inserted = Repo.one(DockerTag)
      assert inserted.inserted_at == inserted.updated_at

      Artifacts.add_docker_tag("hexpm/erlang", "27.0-ubuntu-noble-20250101", ["arm64"])
      updated = Repo.one(DockerTag)
      assert updated.inserted_at == inserted.inserted_at
      assert DateTime.compare(updated.updated_at, inserted.updated_at) == :gt
    end
  end

  describe "stage_docker_tags/3 + swap_docker_tags/2" do
    test "inserts the staged tags with their arch lists" do
      assert replace("hexpm/erlang-amd64", [
               {"27.0-ubuntu-noble-20250101", ["amd64"]},
               {"26.0-ubuntu-noble-20250101", ["amd64"]}
             ]) == :ok

      assert Enum.sort(Artifacts.docker_tags("hexpm/erlang-amd64")) ==
               [
                 {"26.0-ubuntu-noble-20250101", ["amd64"]},
                 {"27.0-ubuntu-noble-20250101", ["amd64"]}
               ]
    end

    test "replaces (does not union) the arch list on conflict" do
      Artifacts.add_docker_tag("hexpm/erlang", "27.0-ubuntu-noble-20250101", ["amd64", "arm64"])

      replace("hexpm/erlang", [{"27.0-ubuntu-noble-20250101", ["amd64"]}])

      assert Artifacts.docker_tags("hexpm/erlang") ==
               [{"27.0-ubuntu-noble-20250101", ["amd64"]}]
    end

    test "prunes rows whose tag is no longer staged" do
      Artifacts.add_docker_tag("hexpm/erlang-amd64", "old-tag", ["amd64"])
      Artifacts.add_docker_tag("hexpm/erlang-amd64", "kept-tag", ["amd64"])

      replace("hexpm/erlang-amd64", [{"kept-tag", ["amd64"]}])

      assert Artifacts.docker_tags("hexpm/erlang-amd64") == [{"kept-tag", ["amd64"]}]
    end

    test "does not touch other repos" do
      Artifacts.add_docker_tag("hexpm/erlang-arm64", "arm-tag", ["arm64"])

      replace("hexpm/erlang-amd64", [{"amd-tag", ["amd64"]}])

      assert Artifacts.docker_tags("hexpm/erlang-arm64") == [{"arm-tag", ["arm64"]}]
    end

    test "collapses duplicate tags staged across pages (Docker Hub returns dupes)" do
      token = Ecto.UUID.generate()
      Artifacts.stage_docker_tags(token, "hexpm/erlang-amd64", [{"27.0", ["amd64"]}])
      Artifacts.stage_docker_tags(token, "hexpm/erlang-amd64", [{"27.0", ["amd64"]}])
      assert Artifacts.swap_docker_tags(token, "hexpm/erlang-amd64") == :ok

      assert Artifacts.docker_tags("hexpm/erlang-amd64") == [{"27.0", ["amd64"]}]
    end

    test "streams more tags than fit in a single statement's parameter limit" do
      token = Ecto.UUID.generate()

      for page <- Enum.chunk_every(1..6000, 100) do
        Artifacts.stage_docker_tags(
          token,
          "hexpm/erlang-amd64",
          Enum.map(page, &{"tag-#{&1}", ["amd64"]})
        )
      end

      assert Artifacts.swap_docker_tags(token, "hexpm/erlang-amd64") == :ok
      assert length(Artifacts.docker_tags("hexpm/erlang-amd64")) == 6000
    end

    test "concurrent tokens for the same repo do not see each other's rows" do
      a = Ecto.UUID.generate()
      b = Ecto.UUID.generate()

      Artifacts.stage_docker_tags(a, "hexpm/erlang-amd64", [{"from-a", ["amd64"]}])
      Artifacts.stage_docker_tags(b, "hexpm/erlang-amd64", [{"from-b", ["amd64"]}])

      assert Artifacts.staged_tag_count(a, "hexpm/erlang-amd64") == 1
      assert Artifacts.swap_docker_tags(a, "hexpm/erlang-amd64") == :ok

      # Swapping token a leaves token b's staged rows untouched.
      assert Artifacts.staged_tag_count(b, "hexpm/erlang-amd64") == 1
      assert Artifacts.docker_tags("hexpm/erlang-amd64") == [{"from-a", ["amd64"]}]
    end
  end

  describe "staged_any?/2" do
    test "is true only when a tag is staged for the token and repo" do
      token = Ecto.UUID.generate()
      Artifacts.stage_docker_tags(token, "hexpm/erlang-amd64", [{"a", ["amd64"]}])

      assert Artifacts.staged_any?(token, "hexpm/erlang-amd64")
      refute Artifacts.staged_any?(token, "hexpm/elixir-amd64")
      refute Artifacts.staged_any?(Ecto.UUID.generate(), "hexpm/erlang-amd64")
    end
  end

  describe "staged_tag_count/2" do
    test "counts distinct staged tags for the token and repo" do
      token = Ecto.UUID.generate()

      Artifacts.stage_docker_tags(token, "hexpm/erlang-amd64", [
        {"a", ["amd64"]},
        {"b", ["amd64"]}
      ])

      Artifacts.stage_docker_tags(token, "hexpm/erlang-amd64", [{"a", ["amd64"]}])

      assert Artifacts.staged_tag_count(token, "hexpm/erlang-amd64") == 2
      assert Artifacts.staged_tag_count(token, "hexpm/elixir-amd64") == 0
    end
  end

  describe "staged_multi_arch_tags/3" do
    test "returns staged tags whose archs cover every requested arch" do
      token = Ecto.UUID.generate()

      Artifacts.stage_docker_tags(token, "library/alpine", [
        {"3.23.5", ["amd64", "arm64", "386"]},
        {"3.22.1", ["amd64"]}
      ])

      assert Artifacts.staged_multi_arch_tags(token, "library/alpine", ["amd64", "arm64"]) ==
               ["3.23.5"]
    end
  end

  describe "discard_staging/1" do
    test "drops every row for the token" do
      token = Ecto.UUID.generate()
      Artifacts.stage_docker_tags(token, "hexpm/erlang-amd64", [{"a", ["amd64"]}])

      assert Artifacts.discard_staging(token) == :ok
      assert Artifacts.staged_tag_count(token, "hexpm/erlang-amd64") == 0
    end
  end

  describe "prune_staging/1" do
    test "deletes rows older than the threshold and keeps fresh ones" do
      token = Ecto.UUID.generate()
      Artifacts.stage_docker_tags(token, "hexpm/erlang-amd64", [{"fresh", ["amd64"]}])

      stale = Ecto.UUID.generate()

      Repo.insert_all(Bob.Artifacts.DockerTagStaging, [
        %{
          token: stale,
          repo: "hexpm/erlang-amd64",
          tag: "stale",
          archs: ["amd64"],
          inserted_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -7 * 60 * 60, :second)
        }
      ])

      assert Artifacts.prune_staging(6 * 60 * 60) == 1
      assert Artifacts.staged_tag_count(token, "hexpm/erlang-amd64") == 1
      assert Artifacts.staged_tag_count(stale, "hexpm/erlang-amd64") == 0
    end
  end

  describe "docker_tags/1" do
    test "scopes to the requested repo" do
      Artifacts.add_docker_tag("hexpm/erlang-amd64", "a", ["amd64"])
      Artifacts.add_docker_tag("hexpm/erlang-arm64", "b", ["arm64"])

      assert Artifacts.docker_tags("hexpm/erlang-amd64") == [{"a", ["amd64"]}]
    end

    test "returns an empty list for an unknown repo" do
      assert Artifacts.docker_tags("hexpm/erlang-amd64") == []
    end
  end

  describe "base_image_tags/1" do
    test "returns the tags for a repo" do
      Repo.insert!(%BaseImageTag{repo: "library/alpine", tag: "3.23.5"})
      Repo.insert!(%BaseImageTag{repo: "library/alpine", tag: "3.22.1"})
      Repo.insert!(%BaseImageTag{repo: "library/ubuntu", tag: "noble-20250101"})

      assert Enum.sort(Artifacts.base_image_tags("library/alpine")) == ["3.22.1", "3.23.5"]
    end
  end

  describe "replace_base_image_tags/2" do
    test "inserts the given tags for the repo" do
      assert Artifacts.replace_base_image_tags("library/alpine", ["3.23.5", "3.22.1"]) == :ok

      assert Enum.sort(Artifacts.base_image_tags("library/alpine")) == ["3.22.1", "3.23.5"]
    end

    test "replaces the previous set for the repo" do
      Repo.insert!(%BaseImageTag{repo: "library/alpine", tag: "3.20.0"})

      Artifacts.replace_base_image_tags("library/alpine", ["3.23.5"])

      assert Artifacts.base_image_tags("library/alpine") == ["3.23.5"]
    end

    test "does not touch other repos" do
      Repo.insert!(%BaseImageTag{repo: "library/ubuntu", tag: "noble-20250101"})

      Artifacts.replace_base_image_tags("library/alpine", ["3.23.5"])

      assert Artifacts.base_image_tags("library/ubuntu") == ["noble-20250101"]
    end

    test "clears the repo when given an empty list" do
      Repo.insert!(%BaseImageTag{repo: "library/alpine", tag: "3.20.0"})

      Artifacts.replace_base_image_tags("library/alpine", [])

      assert Artifacts.base_image_tags("library/alpine") == []
    end

    test "deduplicates repeated tags (Docker Hub can return dupes)" do
      assert Artifacts.replace_base_image_tags("library/alpine", ["3.23.5", "3.23.5"]) == :ok

      assert Artifacts.base_image_tags("library/alpine") == ["3.23.5"]
    end
  end

  defp replace(repo, tag_archs) do
    token = Ecto.UUID.generate()
    Artifacts.stage_docker_tags(token, repo, tag_archs)
    Artifacts.swap_docker_tags(token, repo)
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

  defp row(name, ref, sha256) do
    %{
      kind: "otp",
      arch: "amd64",
      os: "ubuntu-24.04",
      name: name,
      ref: ref,
      sha256: sha256,
      built_at: ~U[2026-01-02 03:04:05.000000Z]
    }
  end
end
