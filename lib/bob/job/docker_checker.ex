defmodule Bob.Job.DockerChecker do
  @erlang_tag_regex ~r"^(.+)-(alpine|ubuntu|debian)-(.+)$"
  @elixir_tag_regex ~r"^(.+)-erlang-(.+)-(alpine|ubuntu|debian)-(.+)$"

  @archs ["amd64", "arm64"]

  def run() do
    erlang()
    elixir()
    manifest()
  end

  def run(:erlang), do: erlang()
  def run(:elixir), do: elixir()
  def run(:manifest), do: manifest()

  def priority(), do: 1
  def weight(), do: 1

  def erlang() do
    tags = erlang_tags()
    expected_tags = expected_erlang_tags()

    Enum.each(diff(expected_tags, tags), fn {erlang, os, os_version, arch} ->
      Bob.Queue.add({Bob.Job.BuildDockerErlang, arch}, [erlang, os, os_version])
    end)
  end

  def expected_erlang_tags() do
    refs = erlang_refs()

    for {os, os_versions} <- Bob.DockerHub.OSVersions.get_os_versions(),
        ref <- refs,
        build_erlang_ref?(os, ref),
        os_version <- os_versions,
        build_erlang_ref?(os, os_version, ref),
        arch <- @archs,
        build_erlang_ref?(arch, os, os_version, ref),
        "OTP-" <> erlang = ref,
        key = {erlang, os, os_diff(os, os_version), arch},
        value = {erlang, os, os_version, arch},
        do: {key, value}
  end

  defp build_erlang_ref?(_os, "OTP-18.0-rc2"), do: false

  defp build_erlang_ref?("alpine", "OTP-17" <> _), do: false
  defp build_erlang_ref?("alpine", "OTP-18" <> _), do: false
  defp build_erlang_ref?("alpine", "OTP-19" <> _), do: false
  defp build_erlang_ref?("alpine", "OTP-20" <> _), do: false
  defp build_erlang_ref?("alpine", "OTP-" <> version), do: build_alpine?(version)
  defp build_erlang_ref?(_os, "OTP-" <> _), do: true
  defp build_erlang_ref?(_os, _ref), do: false

  defp build_erlang_ref?("alpine", os_ver, "OTP-" <> ver), do: build_alpine?(os_ver, ver)
  defp build_erlang_ref?("debian", "buster-" <> _, "OTP-17" <> _), do: false
  defp build_erlang_ref?("debian", "buster-" <> _, "OTP-18" <> _), do: false
  defp build_erlang_ref?("debian", "buster-" <> _, "OTP-19" <> _), do: false
  defp build_erlang_ref?("ubuntu", "focal-" <> _, "OTP-17" <> _), do: false
  defp build_erlang_ref?("ubuntu", "focal-" <> _, "OTP-18" <> _), do: false
  defp build_erlang_ref?("ubuntu", "focal-" <> _, "OTP-19" <> _), do: false
  defp build_erlang_ref?(_os, _os_version, _ref), do: true

  defp build_erlang_ref?("arm64", "ubuntu", "trusty-" <> _, "OTP-17" <> _), do: false
  defp build_erlang_ref?("arm64", "ubuntu", "trusty-" <> _, "OTP-18" <> _), do: false
  defp build_erlang_ref?("arm64", "debian", "jessie-" <> _, _ref), do: false
  defp build_erlang_ref?(_arch, _os, _os_version, _ref), do: true

  defp build_alpine?(version) do
    version = parse_otp_ref(version)

    cond do
      version >= [21] and version < [22] ->
        not (version >= [21, 3] and version <= [21, 3, 8, 19])

      version >= [22, 3] and version < [23] ->
        true

      version >= [23] ->
        true

      true ->
        false
    end
  end

  defp build_alpine?(alpine_version, erlang_version) do
    alpine_version = version_to_list(alpine_version)
    erlang_version = parse_otp_ref(erlang_version)

    cond do
      alpine_version >= [3, 14] ->
        erlang_version >= [23, 2, 2]

      true ->
        true
    end
  end

  defp parse_otp_ref("OTP-" <> version), do: parse_otp_ref(version)

  defp parse_otp_ref(ref) do
    ref
    |> String.split("-")
    |> hd()
    |> version_to_list()
  end

  defp version_to_list(version) do
    version
    |> String.split(".")
    |> Enum.map(&String.to_integer/1)
  end

  defp erlang_refs() do
    "erlang/otp"
    |> Bob.GitHub.fetch_repo_refs()
    |> Enum.map(fn {ref_name, _ref} -> ref_name end)
  end

  def erlang_tags() do
    Enum.flat_map(@archs, &erlang_tags/1)
  end

  def erlang_tags(arch) do
    "hexpm/erlang-#{arch}"
    |> Bob.DockerHub.fetch_repo_tags()
    |> Enum.map(fn {tag, [^arch]} ->
      [erlang, os, os_version] = Regex.run(@erlang_tag_regex, tag, capture: :all_but_first)
      key = {erlang, os, os_diff(os, os_version), arch}
      value = {erlang, os, os_version, arch}
      {key, value}
    end)
  end

  def elixir() do
    tags = elixir_tags()
    expected_tags = expected_elixir_tags()

    Enum.each(diff(expected_tags, tags), fn {elixir, erlang, os, os_version, arch} ->
      Bob.Queue.add({Bob.Job.BuildDockerElixir, arch}, [elixir, erlang, os, os_version])
    end)
  end

  def expected_elixir_tags() do
    # TODO: Base this on builds.txt instead

    refs = elixir_refs()

    tags =
      for arch <- @archs,
          {_, {erlang, os, os_version, ^arch}} <- erlang_tags(arch),
          ref <- refs,
          "v" <> elixir = ref,
          not skip_elixir?(elixir, erlang),
          compatible_elixir_and_erlang?(ref, erlang),
          key = {elixir, erlang, os, os_diff(os, os_version), arch},
          value = {elixir, erlang, os, os_version, arch},
          do: {key, value}

    tags
    |> Enum.sort(:desc)
    |> Enum.uniq_by(fn {key, _value} -> key end)
    |> Enum.map(fn {_key, value} -> {value, value} end)
  end

  defp elixir_refs() do
    "elixir-lang/elixir"
    |> Bob.GitHub.fetch_repo_refs()
    |> Enum.map(fn {ref_name, _ref} -> ref_name end)
    |> Enum.filter(&build_elixir_ref?/1)
  end

  def elixir_tags() do
    Enum.flat_map(@archs, &elixir_tags/1)
  end

  def elixir_tags(arch) do
    "hexpm/elixir-#{arch}"
    |> Bob.DockerHub.fetch_repo_tags()
    |> Enum.map(fn {tag, [^arch]} ->
      [elixir, erlang, os, os_version] =
        Regex.run(@elixir_tag_regex, tag, capture: :all_but_first)

      key = {elixir, erlang, os, os_version, arch}
      {key, key}
    end)
  end

  defp build_elixir_ref?("v0." <> _), do: false

  defp build_elixir_ref?("v" <> version) do
    case Version.parse(version) do
      # don't build RCs for < 1.12
      {:ok, %Version{major: 1, minor: minor, pre: pre}} when minor < 12 and pre != [] -> false
      {:ok, %Version{}} -> true
      :error -> false
    end
  end

  defp build_elixir_ref?(_), do: false

  def diff(expected, current) do
    current = MapSet.new(current, fn {key, _value} -> key end)

    Enum.flat_map(expected, fn {key, value} ->
      if MapSet.member?(current, key) do
        []
      else
        [value]
      end
    end)
    |> Enum.sort()
  end

  defp compatible_elixir_and_erlang?(elixir_ref, erlang) do
    elixir_ref
    |> Bob.Job.BuildElixir.elixir_to_otp()
    |> Enum.map(&List.first(String.split(&1, ".")))
    |> Enum.any?(&String.starts_with?(erlang, &1))
  end

  defp skip_elixir?(elixir, erlang) when elixir in ~w(1.0.0 1.0.1 1.0.2 1.0.3),
    do: String.starts_with?(erlang, "17.5")

  defp skip_elixir?("1.0.5", "18.0-rc1"), do: true
  defp skip_elixir?(_elixir, _erlang), do: false

  def manifest() do
    erlang_tags = group_archs(erlang_tags())
    erlang_manifest_tags = erlang_manifest_tags()
    diff_manifests("erlang", erlang_tags, erlang_manifest_tags)

    elixir_tags = group_archs(elixir_tags())
    elixir_manifest_tags = elixir_manifest_tags()
    diff_manifests("elixir", elixir_tags, elixir_manifest_tags)
  end

  def erlang_manifest_tags() do
    "hexpm/erlang"
    |> Bob.DockerHub.fetch_repo_tags()
    |> Map.new(fn {tag, archs} ->
      [erlang, os, os_version] = Regex.run(@erlang_tag_regex, tag, capture: :all_but_first)
      {{erlang, os, os_version}, archs}
    end)
  end

  def elixir_manifest_tags() do
    "hexpm/elixir"
    |> Bob.DockerHub.fetch_repo_tags()
    |> Map.new(fn {tag, archs} ->
      [elixir, erlang, os, os_version] =
        Regex.run(@elixir_tag_regex, tag, capture: :all_but_first)

      {{elixir, erlang, os, os_version}, archs}
    end)
  end

  defp group_archs(enum) do
    enum
    |> Enum.map(fn {_key, value} -> value end)
    |> Enum.group_by(
      &Tuple.delete_at(&1, tuple_size(&1) - 1),
      &elem(&1, tuple_size(&1) - 1)
    )
  end

  defp diff_manifests(kind, expected, current) do
    Enum.each(Enum.sort(expected), fn {key, expected_archs} ->
      if expected_archs -- Map.get(current, key, []) != [] do
        Bob.Queue.add(Bob.Job.DockerManifest, [kind, key])
      end
    end)
  end

  defp os_diff("alpine", version) do
    version = Version.parse!(version)
    {version.major, version.minor}
  end

  defp os_diff(os, version) when os in ["ubuntu", "debian"] do
    [version, _] = String.split(version, "-", parts: 2)
    version
  end
end
