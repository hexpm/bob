defmodule Bob.DockerHub.OSVersionsSelectorTest do
  use ExUnit.Case, async: true

  alias Bob.DockerHub.OSVersionsSelector

  describe "select/2" do
    test "gets the 2 latest alpine versions" do
      assert OSVersionsSelector.select(:alpine, docker_tags(false)) == ["3.14.0", "3.13.5"]
    end

    test "doesn't pick up a new alpine minor version" do
      assert OSVersionsSelector.select(:alpine, docker_tags(true)) == ["3.14.0", "3.13.5"]
    end

    defp docker_tags(with_new_tags) do
      new_tags = [
        {"3.15.0", ["arm", "amd64", "s390x", "arm64", "386", "ppc64le"]},
        {"3.15", ["arm", "amd64", "s390x", "arm64", "386", "ppc64le"]}
      ]

      docker_tags = [
        {"latest", ["arm", "arm64", "386", "amd64", "ppc64le", "s390x"]},
        {"edge", ["arm", "386", "ppc64le", "arm64", "s390x", "amd64"]},
        {"3.14.0", ["arm", "amd64", "s390x", "arm64", "386", "ppc64le"]},
        {"3.14", ["arm", "amd64", "s390x", "arm64", "386", "ppc64le"]},
        {"3.13.5", ["arm", "amd64", "s390x", "arm64", "386", "ppc64le"]},
        {"3.13.4", ["arm", "amd64", "s390x", "arm64", "386", "ppc64le"]},
        {"3.13", ["arm", "arm64", "amd64", "ppc64le", "s390x", "386"]},
        {"3.12.7", ["arm", "386", "ppc64le", "amd64", "arm64", "s390x"]},
        {"3.12.6", ["arm", "386", "ppc64le", "amd64", "arm64", "s390x"]},
        {"3.12", ["arm", "s390x", "arm64", "ppc64le", "386", "amd64"]},
        {"20210212", ["arm", "arm64", "ppc64le", "amd64", "386", "s390x"]},
        {"3.11.11", ["arm", "arm64", "amd64", "s390x", "ppc64le", "386"]},
        {"3.11.10", ["arm", "arm64", "amd64", "s390x", "ppc64le", "386"]},
        {"3.11", ["arm", "s390x", "ppc64le", "386", "amd64", "arm64"]}
      ]

      if with_new_tags, do: new_tags ++ docker_tags, else: docker_tags
    end
  end
end
