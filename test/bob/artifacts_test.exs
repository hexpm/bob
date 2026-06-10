defmodule Bob.ArtifactsTest do
  use Bob.DataCase

  alias Bob.Artifacts
  alias Bob.Artifacts.{Artifact, BaseImageTag, DockerTag, DockerTagStaging}

  @docker_built_at ~U[2025-01-02 03:04:05.000000Z]
  @newer_docker_built_at ~U[2025-02-03 04:05:06.000000Z]

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

    test "stores parsed search metadata" do
      Artifacts.add_docker_tag("hexpm/elixir-amd64", "1.18.0-erlang-27.0-ubuntu-noble-20250101", [
        "amd64"
      ])

      assert [
               %DockerTag{
                 search: %{
                   "elixir_version" => "1.18.0",
                   "erlang_version" => "27.0",
                   "os" => "ubuntu",
                   "os_version" => "noble-20250101"
                 }
               }
             ] = Repo.all(DockerTag)
    end

    test "stores the supplied Docker Hub timestamp as built_at" do
      Artifacts.add_docker_tag(
        "hexpm/erlang-amd64",
        "27.0-ubuntu-noble-20250101",
        ["amd64"],
        @docker_built_at
      )

      assert [%DockerTag{built_at: @docker_built_at}] = Repo.all(DockerTag)
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
    test "stages and swaps parsed search metadata" do
      token = Ecto.UUID.generate()

      Artifacts.stage_docker_tags(token, "hexpm/erlang-amd64", [
        docker_tag("27.0-ubuntu-noble-20250101", ["amd64"])
      ])

      assert [
               %DockerTagStaging{
                 built_at: @docker_built_at,
                 search: %{
                   "erlang_version" => "27.0",
                   "os" => "ubuntu",
                   "os_version" => "noble-20250101"
                 }
               }
             ] = Repo.all(DockerTagStaging)

      assert Artifacts.swap_docker_tags(token, "hexpm/erlang-amd64") == :ok

      assert [
               %DockerTag{
                 search: %{
                   "erlang_version" => "27.0",
                   "os" => "ubuntu",
                   "os_version" => "noble-20250101"
                 }
               }
             ] = Repo.all(DockerTag)
    end

    test "swaps the staged Docker Hub timestamp into built_at" do
      replace("hexpm/erlang-amd64", [
        docker_tag("27.0-ubuntu-noble-20250101", ["amd64"], @docker_built_at)
      ])

      assert [%DockerTag{built_at: @docker_built_at}] = Repo.all(DockerTag)
    end

    test "updates built_at for otherwise unchanged rows" do
      Artifacts.add_docker_tag(
        "hexpm/erlang-amd64",
        "27.0-ubuntu-noble-20250101",
        ["amd64"],
        @docker_built_at
      )

      inserted = Repo.one(DockerTag)

      replace("hexpm/erlang-amd64", [
        docker_tag("27.0-ubuntu-noble-20250101", ["amd64"], @newer_docker_built_at)
      ])

      updated = Repo.one(DockerTag)
      assert updated.built_at == @newer_docker_built_at
      assert DateTime.compare(updated.updated_at, inserted.updated_at) == :gt
    end

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

      Artifacts.stage_docker_tags(token, "hexpm/erlang-amd64", [
        docker_tag("27.0", ["amd64"], @docker_built_at)
      ])

      Artifacts.stage_docker_tags(token, "hexpm/erlang-amd64", [
        docker_tag("27.0", ["amd64"], @newer_docker_built_at)
      ])

      assert Artifacts.swap_docker_tags(token, "hexpm/erlang-amd64") == :ok

      assert Artifacts.docker_tags("hexpm/erlang-amd64") == [{"27.0", ["amd64"]}]
      assert [%DockerTag{built_at: @newer_docker_built_at}] = Repo.all(DockerTag)
    end

    test "streams more tags than fit in a single statement's parameter limit" do
      token = Ecto.UUID.generate()

      for page <- Enum.chunk_every(1..6000, 100) do
        Artifacts.stage_docker_tags(
          token,
          "hexpm/erlang-amd64",
          Enum.map(page, &docker_tag("tag-#{&1}", ["amd64"]))
        )
      end

      assert Artifacts.swap_docker_tags(token, "hexpm/erlang-amd64") == :ok
      assert length(Artifacts.docker_tags("hexpm/erlang-amd64")) == 6000
    end

    test "concurrent tokens for the same repo do not see each other's rows" do
      a = Ecto.UUID.generate()
      b = Ecto.UUID.generate()

      Artifacts.stage_docker_tags(a, "hexpm/erlang-amd64", [
        docker_tag("from-a", ["amd64"])
      ])

      Artifacts.stage_docker_tags(b, "hexpm/erlang-amd64", [
        docker_tag("from-b", ["amd64"])
      ])

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

      Artifacts.stage_docker_tags(token, "hexpm/erlang-amd64", [
        docker_tag("a", ["amd64"])
      ])

      assert Artifacts.staged_any?(token, "hexpm/erlang-amd64")
      refute Artifacts.staged_any?(token, "hexpm/elixir-amd64")
      refute Artifacts.staged_any?(Ecto.UUID.generate(), "hexpm/erlang-amd64")
    end
  end

  describe "staged_tag_count/2" do
    test "counts distinct staged tags for the token and repo" do
      token = Ecto.UUID.generate()

      Artifacts.stage_docker_tags(token, "hexpm/erlang-amd64", [
        docker_tag("a", ["amd64"]),
        docker_tag("b", ["amd64"])
      ])

      Artifacts.stage_docker_tags(token, "hexpm/erlang-amd64", [
        docker_tag("a", ["amd64"])
      ])

      assert Artifacts.staged_tag_count(token, "hexpm/erlang-amd64") == 2
      assert Artifacts.staged_tag_count(token, "hexpm/elixir-amd64") == 0
    end
  end

  describe "staged_multi_arch_tags/3" do
    test "returns staged tags whose archs cover every requested arch" do
      token = Ecto.UUID.generate()

      Artifacts.stage_docker_tags(token, "library/alpine", [
        docker_tag("3.23.5", ["amd64", "arm64", "386"]),
        docker_tag("3.22.1", ["amd64"])
      ])

      assert Artifacts.staged_multi_arch_tags(token, "library/alpine", ["amd64", "arm64"]) ==
               ["3.23.5"]
    end
  end

  describe "discard_staging/1" do
    test "drops every row for the token" do
      token = Ecto.UUID.generate()

      Artifacts.stage_docker_tags(token, "hexpm/erlang-amd64", [
        docker_tag("a", ["amd64"])
      ])

      assert Artifacts.discard_staging(token) == :ok
      assert Artifacts.staged_tag_count(token, "hexpm/erlang-amd64") == 0
    end
  end

  describe "prune_staging/1" do
    test "deletes rows older than the threshold and keeps fresh ones" do
      token = Ecto.UUID.generate()

      Artifacts.stage_docker_tags(token, "hexpm/erlang-amd64", [
        docker_tag("fresh", ["amd64"])
      ])

      stale = Ecto.UUID.generate()

      Repo.insert_all(Bob.Artifacts.DockerTagStaging, [
        %{
          token: stale,
          repo: "hexpm/erlang-amd64",
          tag: "stale",
          archs: ["amd64"],
          built_at: @docker_built_at,
          inserted_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -7 * 60 * 60, :second)
        }
      ])

      assert Artifacts.prune_staging(6 * 60 * 60) == 1
      assert Artifacts.staged_tag_count(token, "hexpm/erlang-amd64") == 1
      assert Artifacts.staged_tag_count(stale, "hexpm/erlang-amd64") == 0
    end
  end

  describe "docker_tags_present/2" do
    test "returns the subset of the given tags that exist for the repo" do
      Artifacts.add_docker_tag("hexpm/erlang-amd64", "27.0-ubuntu-noble-20250101", ["amd64"])
      Artifacts.add_docker_tag("hexpm/erlang-amd64", "26.2-ubuntu-noble-20250101", ["amd64"])
      Artifacts.add_docker_tag("hexpm/erlang-arm64", "25.3-ubuntu-noble-20250101", ["arm64"])

      present =
        Artifacts.docker_tags_present("hexpm/erlang-amd64", [
          "27.0-ubuntu-noble-20250101",
          "30.0-ubuntu-noble-20250101",
          "25.3-ubuntu-noble-20250101"
        ])

      assert present == MapSet.new(["27.0-ubuntu-noble-20250101"])
    end

    test "returns an empty set for no tags" do
      assert Artifacts.docker_tags_present("hexpm/erlang-amd64", []) == MapSet.new()
    end
  end

  describe "erlang_tags_for_os_versions/2" do
    test "returns repo and tag for the requested repos and os_versions only" do
      Artifacts.add_docker_tag("hexpm/erlang-amd64", "27.0-ubuntu-noble-20250101", ["amd64"])
      Artifacts.add_docker_tag("hexpm/erlang-arm64", "27.0-alpine-3.23.5", ["arm64"])
      Artifacts.add_docker_tag("hexpm/erlang-amd64", "26.2-ubuntu-noble-20240101", ["amd64"])

      Artifacts.add_docker_tag(
        "hexpm/elixir-amd64",
        "1.18.0-erlang-27.0-ubuntu-noble-20250101",
        ["amd64"]
      )

      tags =
        Artifacts.erlang_tags_for_os_versions(
          ["hexpm/erlang-amd64", "hexpm/erlang-arm64"],
          ["noble-20250101", "3.23.5"]
        )

      assert Enum.sort(tags) == [
               {"hexpm/erlang-amd64", "27.0-ubuntu-noble-20250101"},
               {"hexpm/erlang-arm64", "27.0-alpine-3.23.5"}
             ]
    end
  end

  describe "manifest_mismatches/3" do
    test "returns per-arch tags that have no manifest at all" do
      Artifacts.add_docker_tag("hexpm/erlang-amd64", "27.0-ubuntu-noble-20250101", ["amd64"])
      Artifacts.add_docker_tag("hexpm/erlang-arm64", "27.0-ubuntu-noble-20250101", ["arm64"])

      assert Artifacts.manifest_mismatches(
               "hexpm/erlang",
               "hexpm/erlang-amd64",
               "hexpm/erlang-arm64"
             ) == [{"27.0-ubuntu-noble-20250101", ["amd64", "arm64"]}]
    end

    test "returns tags whose manifest lacks one of the built archs" do
      Artifacts.add_docker_tag("hexpm/erlang-amd64", "27.0-ubuntu-noble-20250101", ["amd64"])
      Artifacts.add_docker_tag("hexpm/erlang-arm64", "27.0-ubuntu-noble-20250101", ["arm64"])
      Artifacts.add_docker_tag("hexpm/erlang", "27.0-ubuntu-noble-20250101", ["amd64"])

      assert Artifacts.manifest_mismatches(
               "hexpm/erlang",
               "hexpm/erlang-amd64",
               "hexpm/erlang-arm64"
             ) == [{"27.0-ubuntu-noble-20250101", ["amd64", "arm64"]}]
    end

    test "skips tags whose manifest covers every built arch" do
      Artifacts.add_docker_tag("hexpm/erlang-amd64", "27.0-ubuntu-noble-20250101", ["amd64"])
      Artifacts.add_docker_tag("hexpm/erlang-arm64", "27.0-ubuntu-noble-20250101", ["arm64"])
      Artifacts.add_docker_tag("hexpm/erlang", "27.0-ubuntu-noble-20250101", ["amd64", "arm64"])

      assert Artifacts.manifest_mismatches(
               "hexpm/erlang",
               "hexpm/erlang-amd64",
               "hexpm/erlang-arm64"
             ) == []
    end

    test "skips a manifest that has more archs than were built" do
      Artifacts.add_docker_tag("hexpm/erlang-amd64", "27.0-ubuntu-noble-20250101", ["amd64"])
      Artifacts.add_docker_tag("hexpm/erlang", "27.0-ubuntu-noble-20250101", ["amd64", "arm64"])

      assert Artifacts.manifest_mismatches(
               "hexpm/erlang",
               "hexpm/erlang-amd64",
               "hexpm/erlang-arm64"
             ) == []
    end

    test "ignores tags that only exist in the manifest repo" do
      Artifacts.add_docker_tag("hexpm/erlang", "27.0-ubuntu-noble-20250101", ["amd64", "arm64"])

      assert Artifacts.manifest_mismatches(
               "hexpm/erlang",
               "hexpm/erlang-amd64",
               "hexpm/erlang-arm64"
             ) == []
    end

    test "returns a single-arch tag without a manifest with just that arch" do
      Artifacts.add_docker_tag("hexpm/erlang-arm64", "27.0-ubuntu-noble-20250101", ["arm64"])

      assert Artifacts.manifest_mismatches(
               "hexpm/erlang",
               "hexpm/erlang-amd64",
               "hexpm/erlang-arm64"
             ) == [{"27.0-ubuntu-noble-20250101", ["arm64"]}]
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

  describe "search" do
    setup do
      Bob.Artifacts.upsert(%{
        kind: "otp",
        arch: "amd64",
        os: "ubuntu-24.04",
        name: "OTP-27.0",
        ref: "aaa",
        built_at: ~U[2026-01-01 00:00:00Z]
      })

      Bob.Artifacts.upsert(%{
        kind: "otp",
        arch: "arm64",
        os: "ubuntu-22.04",
        name: "OTP-26.2",
        ref: "bbb",
        built_at: ~U[2026-02-01 00:00:00Z]
      })

      :ok
    end

    test "search_artifacts/1 with blank filters returns newest first" do
      assert [%{name: "OTP-26.2"}, %{name: "OTP-27.0"}] = Bob.Artifacts.search_artifacts(%{})
    end

    test "search_docker_tags/1 with blank filters returns newest first" do
      Bob.Artifacts.add_docker_tag(
        "hexpm/erlang",
        "old-ubuntu-noble-20250101",
        ["amd64"],
        ~U[2025-01-01 00:00:00Z]
      )

      Bob.Artifacts.add_docker_tag(
        "hexpm/erlang",
        "new-ubuntu-noble-20250101",
        ["amd64"],
        ~U[2025-02-01 00:00:00Z]
      )

      assert [%{tag: "new-ubuntu-noble-20250101"}, %{tag: "old-ubuntu-noble-20250101"}] =
               Bob.Artifacts.search_docker_tags(%{})
    end

    test "search_artifacts/1 filters by free-text on name" do
      assert [%{name: "OTP-27.0"}] = Bob.Artifacts.search_artifacts(%{query: "27.0"})
    end

    test "search_artifacts/1 filters by arch" do
      assert [%{arch: "arm64"}] = Bob.Artifacts.search_artifacts(%{arch: "arm64"})
    end

    test "count_artifacts/1 counts exact matching artifacts" do
      assert Bob.Artifacts.count_artifacts(%{}) == 2
      assert Bob.Artifacts.count_artifacts(%{query: "27.0"}) == 1
      assert Bob.Artifacts.count_artifacts(%{arch: "arm64"}) == 1
      assert Bob.Artifacts.count_artifacts(%{os: "missing"}) == 0
    end

    test "distinct value helpers" do
      assert Bob.Artifacts.distinct_kinds() == ["otp"]
      assert Bob.Artifacts.distinct_arches() == ["amd64", "arm64"]
      assert Bob.Artifacts.distinct_oses() == ["ubuntu-22.04", "ubuntu-24.04"]
    end

    test "distinct Docker filter helpers" do
      assert Bob.Artifacts.distinct_docker_arches() == ["amd64", "arm64"]
      assert Bob.Artifacts.distinct_docker_oses() == ["alpine", "debian", "ubuntu"]
    end

    test "distinct Docker repositories" do
      Bob.Artifacts.add_docker_tag("hexpm/erlang", "27.0-ubuntu-noble-20250101", [
        "amd64",
        "arm64"
      ])

      Bob.Artifacts.add_docker_tag(
        "hexpm/elixir",
        "1.17.3-erlang-26.2-debian-bookworm-20250113-slim",
        ["amd64"]
      )

      assert Bob.Artifacts.distinct_repos() == ["hexpm/elixir", "hexpm/erlang"]
    end

    test "search_docker_tags/1 filters by structured prefixes" do
      Bob.Artifacts.add_docker_tag("hexpm/erlang", "27.0-ubuntu-noble-20250101", [
        "amd64",
        "arm64"
      ])

      Bob.Artifacts.add_docker_tag("hexpm/erlang", "27.1-ubuntu-noble-20250101", [
        "amd64"
      ])

      Bob.Artifacts.add_docker_tag("hexpm/erlang", "26.2-debian-bookworm-20250113-slim", [
        "amd64"
      ])

      Bob.Artifacts.add_docker_tag(
        "hexpm/elixir",
        "1.18.0-erlang-27.0-ubuntu-noble-20250101",
        ["amd64", "arm64"]
      )

      Bob.Artifacts.add_docker_tag(
        "hexpm/elixir",
        "1.17.3-erlang-26.2-debian-bookworm-20250113-slim",
        ["amd64"]
      )

      assert [%{tag: "27.0-ubuntu-noble-20250101"}] =
               Bob.Artifacts.search_docker_tags(%{
                 repo: "hexpm/erl",
                 tag: "27",
                 arch: "arm",
                 erlang_version: "27",
                 os: "ub",
                 os_version: "noble"
               })

      assert [%{tag: "27.0-ubuntu-noble-20250101"}] =
               Bob.Artifacts.search_docker_tags(%{
                 repo: "hexpm/erl",
                 tag: "27",
                 arch: "arm",
                 os: "ub",
                 os_version: "noble"
               })

      assert [
               "1.17.3-erlang-26.2-debian-bookworm-20250113-slim",
               "1.18.0-erlang-27.0-ubuntu-noble-20250101"
             ] =
               Bob.Artifacts.search_docker_tags(%{elixir_version: "1"})
               |> Enum.map(& &1.tag)
               |> Enum.sort()

      assert [
               "1.18.0-erlang-27.0-ubuntu-noble-20250101",
               "27.0-ubuntu-noble-20250101",
               "27.1-ubuntu-noble-20250101"
             ] =
               Bob.Artifacts.search_docker_tags(%{os: "ub"})
               |> Enum.map(& &1.tag)
               |> Enum.sort()

      assert [%{tag: "1.18.0-erlang-27.0-ubuntu-noble-20250101"}] =
               Bob.Artifacts.search_docker_tags(%{
                 elixir_version: "1",
                 os: "ub"
               })

      assert [%{tag: "1.18.0-erlang-27.0-ubuntu-noble-20250101"}] =
               Bob.Artifacts.search_docker_tags(%{
                 repo: "hexpm/elixir",
                 elixir_version: "1.18",
                 erlang_version: "27.0",
                 os: "ubuntu",
                 os_version: "noble-2025"
               })

      assert [%{tag: "1.17.3-erlang-26.2-debian-bookworm-20250113-slim"}] =
               Bob.Artifacts.search_docker_tags(%{
                 elixir_version: "1.17",
                 os: "deb",
                 os_version: "bookworm"
               })
    end

    test "count_docker_tags/1 counts exact matching tags" do
      Bob.Artifacts.add_docker_tag("hexpm/erlang", "27.0-ubuntu-noble-20250101", [
        "amd64",
        "arm64"
      ])

      Bob.Artifacts.add_docker_tag("hexpm/erlang", "27.1-ubuntu-noble-20250101", ["arm64"])

      count =
        Bob.Artifacts.count_docker_tags(%{
          repo: "hexpm/erl",
          tag: "27",
          arch: "arm",
          erlang_version: "27",
          os: "ub",
          os_version: "noble"
        })

      assert count == 2
      assert Bob.Artifacts.count_docker_tags(%{arch: "amd64"}) == 1
      assert Bob.Artifacts.count_docker_tags(%{arch: "arm64"}) == 2
      assert Bob.Artifacts.count_docker_tags(%{tag: "missing"}) == 0
    end

    test "search_artifacts/1 does not treat % as a LIKE wildcard" do
      assert Bob.Artifacts.search_artifacts(%{query: "%"}) == []
    end

    test "search_docker_tags/1 does not treat % or _ as LIKE wildcards" do
      Bob.Artifacts.add_docker_tag("hexpm/erlang", "27.0-ubuntu-noble-20250101", ["amd64"])

      assert Bob.Artifacts.search_docker_tags(%{tag: "%"}) == []
      assert Bob.Artifacts.search_docker_tags(%{repo: "hexpm/_"}) == []
      assert Bob.Artifacts.search_docker_tags(%{arch: "%"}) == []
      assert Bob.Artifacts.search_docker_tags(%{erlang_version: "%"}) == []
      assert Bob.Artifacts.search_docker_tags(%{erlang_version: "27_"}) == []
    end

    test "search_artifacts/3 respects limit and offset" do
      assert [%{name: "OTP-26.2"}] = Bob.Artifacts.search_artifacts(%{}, 1, 0)
      assert [%{name: "OTP-27.0"}] = Bob.Artifacts.search_artifacts(%{}, 1, 1)
    end
  end

  defp replace(repo, tag_archs) do
    token = Ecto.UUID.generate()
    Artifacts.stage_docker_tags(token, repo, Enum.map(tag_archs, &docker_tag_tuple/1))
    Artifacts.swap_docker_tags(token, repo)
  end

  defp docker_tag(tag, archs, built_at \\ @docker_built_at), do: {tag, archs, built_at}

  defp docker_tag_tuple({tag, archs}), do: docker_tag(tag, archs)
  defp docker_tag_tuple({tag, archs, built_at}), do: docker_tag(tag, archs, built_at)

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
