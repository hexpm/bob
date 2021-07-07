defmodule Bob.DockerHub.OSVersions do
  alias Bob.DockerHub

  # TODO: Automate picking ubuntu and debian os versions

  @static_os_versions %{
    "ubuntu" => [
      "groovy-20210325",
      "focal-20210325",
      "bionic-20210325",
      "xenial-20210114",
      "trusty-20191217"
    ],
    "debian" => [
      "buster-20210326",
      "stretch-20210326",
      "jessie-20210326"
    ]
  }

  def get_os_versions do
    Map.put(@static_os_versions, "alpine", get_alpine_versions())
  end

  defp get_alpine_versions() do
    DockerHub.OSVersionsSelector.select(:alpine, Bob.DockerHub.fetch_repo_tags("library/alpine"))
  end
end
