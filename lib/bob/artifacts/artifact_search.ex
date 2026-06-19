defmodule Bob.Artifacts.ArtifactSearch do
  @page 100
  @filter_keys ~w(query kind arch os)a

  def page_size(), do: @page
  def filter_keys(), do: @filter_keys

  def parse_filters(params) do
    %{
      query: params["query"] || "",
      kind: params["kind"] || "",
      arch: params["arch"] || "",
      os: params["os"] || ""
    }
  end

  def parse_offset(params) do
    case Integer.parse(params["offset"] || "") do
      {offset, ""} when offset > 0 -> offset
      _ -> 0
    end
  end
end
