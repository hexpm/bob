defmodule Bob.Artifacts.DockerTagSearchTest do
  use ExUnit.Case, async: true

  alias Bob.Artifacts.DockerTagSearch

  test "returns known Docker tag dimensions" do
    assert DockerTagSearch.repos() == [
             "hexpm/elixir",
             "hexpm/elixir-amd64",
             "hexpm/elixir-arm64",
             "hexpm/erlang",
             "hexpm/erlang-amd64",
             "hexpm/erlang-arm64"
           ]

    assert DockerTagSearch.arches() == ["amd64", "arm64"]
    assert DockerTagSearch.oses() == ["alpine", "debian", "ubuntu"]
  end

  test "parses per-arch Erlang tags" do
    assert DockerTagSearch.metadata(
             "hexpm/erlang-amd64",
             "27.0-ubuntu-noble-20250101"
           ) == %{
             "erlang_version" => "27.0",
             "os" => "ubuntu",
             "os_version" => "noble-20250101"
           }
  end

  test "parses Erlang manifest tags" do
    assert DockerTagSearch.metadata(
             "hexpm/erlang",
             "26.2-debian-bookworm-20250113-slim"
           ) == %{
             "erlang_version" => "26.2",
             "os" => "debian",
             "os_version" => "bookworm-20250113-slim"
           }
  end

  test "parses major-only Erlang version tags" do
    assert DockerTagSearch.metadata(
             "hexpm/erlang",
             "17-ubuntu-jammy-20250101"
           ) == %{
             "erlang_version" => "17",
             "os" => "ubuntu",
             "os_version" => "jammy-20250101"
           }
  end

  test "parses Erlang prerelease version tags" do
    assert DockerTagSearch.metadata(
             "hexpm/erlang",
             "26.0-rc1-ubuntu-noble-20250101"
           ) == %{
             "erlang_version" => "26.0-rc1",
             "os" => "ubuntu",
             "os_version" => "noble-20250101"
           }
  end

  test "parses per-arch Elixir tags" do
    assert DockerTagSearch.metadata(
             "hexpm/elixir-arm64",
             "1.18.0-erlang-27.0-ubuntu-noble-20250101"
           ) == %{
             "elixir_version" => "1.18.0",
             "erlang_version" => "27.0",
             "os" => "ubuntu",
             "os_version" => "noble-20250101"
           }
  end

  test "parses Elixir manifest tags" do
    assert DockerTagSearch.metadata(
             "hexpm/elixir",
             "1.17.3-erlang-26.2-alpine-3.22.1"
           ) == %{
             "elixir_version" => "1.17.3",
             "erlang_version" => "26.2",
             "os" => "alpine",
             "os_version" => "3.22.1"
           }
  end

  test "parses Elixir prerelease version tags" do
    assert DockerTagSearch.metadata(
             "hexpm/elixir",
             "1.18.0-rc.0-erlang-27.0-ubuntu-noble-20250101"
           ) == %{
             "elixir_version" => "1.18.0-rc.0",
             "erlang_version" => "27.0",
             "os" => "ubuntu",
             "os_version" => "noble-20250101"
           }
  end

  test "returns empty metadata for unknown repos and malformed tags" do
    assert DockerTagSearch.metadata("library/alpine", "3.22.1") == %{}
    assert DockerTagSearch.metadata("hexpm/erlang-amd64", "not-a-known-shape") == %{}
    assert DockerTagSearch.metadata("hexpm/erlang", "not-ubuntu-shape") == %{}
    assert DockerTagSearch.metadata("hexpm/elixir-amd64", "1.18.0-otp-27") == %{}

    assert DockerTagSearch.metadata("hexpm/elixir", "anything-erlang-anything-debian-shape") ==
             %{}
  end
end
