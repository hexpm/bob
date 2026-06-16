defmodule Bob.DockerHubTest do
  use ExUnit.Case, async: true

  alias Bob.DockerHub

  @built_at ~U[2025-01-02 03:04:05.123456Z]
  @image_pushed_at ~U[2025-02-03 04:05:06.000000Z]
  @last_pulled ~U[2026-06-16 13:17:58.638032Z]

  describe "parse/1" do
    test "returns tag, archs, built_at, and tag_last_pulled" do
      assert DockerHub.parse(
               tag_payload(%{
                 "last_updated" => "2025-01-02T03:04:05.123456Z",
                 "tag_last_pulled" => "2026-06-16T13:17:58.638032692Z",
                 "images" => [
                   image("amd64", "sha256:amd64", "2025-02-03T04:05:06Z"),
                   image("arm64", "sha256:arm64", "2025-02-03T04:05:06Z")
                 ]
               })
             ) == {"27.0", ["amd64", "arm64"], @built_at, @last_pulled}
    end

    test "falls back to image last_pushed when the tag timestamp is absent" do
      assert DockerHub.parse(
               tag_payload(%{
                 "images" => [
                   image("amd64", "sha256:amd64", "2025-01-03T04:05:06Z"),
                   image("arm64", "sha256:arm64", "2025-02-03T04:05:06Z")
                 ]
               })
             ) == {"27.0", ["amd64", "arm64"], @image_pushed_at, nil}
    end

    test "leaves last_pulled nil for a tag that has never been pulled" do
      for never_pulled <- [nil, "", "0001-01-01T00:00:00Z"] do
        assert {"27.0", ["amd64", "arm64"], @built_at, nil} =
                 DockerHub.parse(
                   tag_payload(%{
                     "last_updated" => "2025-01-02T03:04:05.123456Z",
                     "tag_last_pulled" => never_pulled,
                     "images" => [
                       image("amd64", "sha256:amd64", "2025-02-03T04:05:06Z"),
                       image("arm64", "sha256:arm64", "2025-02-03T04:05:06Z")
                     ]
                   })
                 )
      end
    end

    test "rejects images without a digest" do
      assert DockerHub.parse(
               tag_payload(%{
                 "last_updated" => "2025-01-02T03:04:05.123456Z",
                 "images" => [image("amd64", nil, "2025-02-03T04:05:06Z")]
               })
             ) == nil
    end

    test "rejects tags without a Docker Hub timestamp" do
      assert DockerHub.parse(
               tag_payload(%{
                 "images" => [%{"architecture" => "amd64", "digest" => "sha256:amd64"}]
               })
             ) == nil
    end
  end

  defp tag_payload(attrs) do
    Map.merge(
      %{
        "name" => "27.0",
        "images" => []
      },
      attrs
    )
  end

  defp image(arch, digest, last_pushed) do
    %{
      "architecture" => arch,
      "digest" => digest,
      "last_pushed" => last_pushed
    }
  end
end
