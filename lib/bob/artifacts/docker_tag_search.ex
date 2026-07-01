defmodule Bob.Artifacts.DockerTagSearch do
  @archs ~w(amd64 arm64)
  @erlang_repos ~w(hexpm/erlang hexpm/erlang-amd64 hexpm/erlang-arm64)
  @elixir_repos ~w(hexpm/elixir hexpm/elixir-amd64 hexpm/elixir-arm64)
  @oses ~w(alpine debian ubuntu)

  @erlang_tag_regex ~r/^(.+)-(alpine|ubuntu|debian)-(.+)$/
  @elixir_tag_regex ~r/^(.+)-erlang-(.+)-(alpine|ubuntu|debian)-(.+)$/
  @version_regex ~r/^\d+(?:\.\d+)*(?:-[0-9A-Za-z][0-9A-Za-z.-]*)?$/

  @page 100
  @filter_keys ~w(repo tag arch elixir_version erlang_version os os_version)a

  def repos(), do: Enum.sort(@erlang_repos ++ @elixir_repos)
  def arches(), do: @archs
  def oses(), do: @oses

  def page_size(), do: @page
  def filter_keys(), do: @filter_keys

  def parse_filters(params) do
    tag = params["tag"] || ""

    %{
      repo: params["repo"] || "",
      tag: tag,
      arch: params["arch"] || "",
      elixir_version: structured_param(params, "elixir_version", tag),
      erlang_version: structured_param(params, "erlang_version", tag),
      os: structured_param(params, "os", tag),
      os_version: structured_param(params, "os_version", tag)
    }
  end

  def parse_offset(params) do
    case Integer.parse(params["offset"] || "") do
      {offset, ""} when offset > 0 -> offset
      _ -> 0
    end
  end

  defp structured_param(_params, _key, tag) when tag != "", do: ""
  defp structured_param(params, key, _tag), do: params[key] || ""

  def metadata(repo, tag) when repo in @erlang_repos do
    case Regex.run(@erlang_tag_regex, tag, capture: :all_but_first) do
      [erlang_version, os, os_version] ->
        if version?(erlang_version) do
          %{
            "erlang_version" => erlang_version,
            "os" => os,
            "os_version" => os_version
          }
        else
          %{}
        end

      _other ->
        %{}
    end
  end

  def metadata(repo, tag) when repo in @elixir_repos do
    case Regex.run(@elixir_tag_regex, tag, capture: :all_but_first) do
      [elixir_version, erlang_version, os, os_version] ->
        if version?(elixir_version) and version?(erlang_version) do
          %{
            "elixir_version" => elixir_version,
            "erlang_version" => erlang_version,
            "os" => os,
            "os_version" => os_version
          }
        else
          %{}
        end

      _other ->
        %{}
    end
  end

  def metadata(_repo, _tag), do: %{}

  defp version?(version), do: Regex.match?(@version_regex, version)
end
