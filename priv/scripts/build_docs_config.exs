#!/usr/bin/env elixir
#
# Usage: build_docs_config.exs PROJECT VERSIONS

[project, versions_string] = System.argv()
versions = String.split(versions_string, ~r"(\s|\n)", trim: true)

js_objects =
  for version <- versions do
    pretty_version =
      case Version.parse(version) do
        {:ok, version} -> "v#{version}"
        _ -> version
      end

    url = "https://hexdocs.pm/#{project}/#{version}"
    ~s({"version":"#{pretty_version}", "url":"#{url}"})
  end

data = ["var versionNodes = [", Enum.join(js_objects, ", "), "];"]
File.write!("docs_config.js", data)
