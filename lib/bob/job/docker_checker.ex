defmodule Bob.Job.DockerChecker do
  @erlang_tag_regex ~r"^(\d+(?:\.\d+)?(?:\.\d+)?)-([^-]+)-(.+)$"
  @elixir_tag_regex ~r"^(.+)-erlang-([^-]+)-([^-]+)-(.+)$"

  @builds %{
    "alpine" => ["3.11.3"],
    "ubuntu" => ["bionic-20200219", "xenial-20200212", "trusty-20191217"],
    "debian" => ["buster-20200224", "stretch-20200224", "jessie-20200224"]
  }

  def run([]) do
    erlang()
    elixir()
  end

  defp erlang() do
    tags = erlang_tags()
    refs = erlang_refs()

    expected_tags =
      for {operating_system, versions} <- @builds,
          ref <- refs,
          build_erlang_ref?(operating_system, ref),
          "OTP-" <> ref = ref,
          version <- versions,
          do: {ref, operating_system, version}

    Enum.each(diff(expected_tags, tags), fn {ref, os, os_version} ->
      Bob.Queue.add(Bob.Job.BuildDockerErlang, [ref, os, os_version])
    end)
  end

  defp build_erlang_ref?(_os, "OTP-18.0-rc2"), do: false
  defp build_erlang_ref?("alpine", "OTP-17" <> _), do: false
  defp build_erlang_ref?("alpine", "OTP-18" <> _), do: false

  defp build_erlang_ref?(_os, "OTP-" <> version) do
    match?({:ok, %Version{pre: []}}, Version.parse(version)) or
      match?({:ok, %Version{pre: []}}, Version.parse(version <> ".0"))
  end

  defp build_erlang_ref?(_os, _ref), do: false

  defp erlang_refs() do
    "erlang/otp"
    |> Bob.GitHub.fetch_repo_refs()
    |> Enum.map(fn {ref_name, _ref} -> ref_name end)
  end

  defp erlang_tags() do
    "hexpm/erlang"
    |> Bob.DockerHub.fetch_repo_tags()
    |> Enum.map(&parse_erlang_tag/1)
  end

  defp elixir() do
    erlang_tags = erlang_tags()
    refs = elixir_refs()
    tags = elixir_tags()

    expected_tags =
      for ref <- refs,
          "v" <> ref = ref,
          {erlang, os, os_version} <- erlang_tags,
          not skip_elixir?(ref, erlang),
          compatible_elixir_and_erlang?(ref, erlang),
          do: {ref, erlang, os, os_version}

    Enum.each(diff(expected_tags, tags), fn {elixir, erlang, os, os_version} ->
      Bob.Queue.add(Bob.Job.BuildDockerElixir, [elixir, erlang, os, os_version])
    end)
  end

  defp elixir_refs() do
    "elixir-lang/elixir"
    |> Bob.GitHub.fetch_repo_refs()
    |> Enum.map(fn {ref_name, _ref} -> ref_name end)
    |> Enum.filter(&build_elixir_ref?/1)
  end

  defp elixir_tags() do
    "hexpm/elixir"
    |> Bob.DockerHub.fetch_repo_tags()
    |> Enum.map(&parse_elixir_tag/1)
  end

  defp build_elixir_ref?("v0." <> _), do: false

  defp build_elixir_ref?("v" <> version) do
    match?({:ok, %Version{pre: []}}, Version.parse(version))
  end

  defp build_elixir_ref?(_), do: false

  defp parse_erlang_tag(tag) do
    [erlang, os, os_version] = Regex.run(@erlang_tag_regex, tag, capture: :all_but_first)
    {erlang, os, os_version}
  end

  defp parse_elixir_tag(tag) do
    [elixir, erlang, os, os_version] = Regex.run(@elixir_tag_regex, tag, capture: :all_but_first)
    {elixir, erlang, os, os_version}
  end

  defp diff(expected, current) do
    MapSet.difference(MapSet.new(expected), MapSet.new(current))
    |> Enum.sort()
  end

  defp compatible_elixir_and_erlang?(elixir, erlang) do
    compatibles =
      case elixir do
        "1.0.5" -> ["17", "18"]
        "1.0." <> _ -> ["17"]
        "1.1." <> _ -> ["17", "18"]
        "1.2." <> _ -> ["18"]
        "1.3." <> _ -> ["18", "19"]
        "1.4.5" -> ["18", "19", "20"]
        "1.4." <> _ -> ["18", "19"]
        "1.5." <> _ -> ["18", "19", "20"]
        "1.6.6" -> ["19", "20", "21"]
        "1.6." <> _ -> ["19", "20"]
        "1.7." <> _ -> ["19", "20", "21", "22"]
        "1.8." <> _ -> ["20", "21", "22"]
        "1.9." <> _ -> ["20", "21", "22"]
        "1.10." <> _ -> ["21", "22"]
      end

    Enum.any?(compatibles, &String.starts_with?(erlang, &1))
  end

  defp skip_elixir?(elixir, erlang) when elixir in ~w(1.0.0 1.0.1 1.0.2 1.0.3) do
    String.starts_with?(erlang, "17.5")
  end

  defp skip_elixir?(_elixir, _erlang) do
    false
  end
end
