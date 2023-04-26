defmodule Bob.Job.DockerChecker do
  @erlang_tag_regex ~r"^(.+)-(alpine|ubuntu|debian)-(.+)$"
  @elixir_tag_regex ~r"^(.+)-erlang-(.+)-(alpine|ubuntu|debian)-(.+)$"

  @archs ["amd64", "arm64"]

  # TODO: Automate picking the OS versions

  @builds %{
    "alpine" => [
      "3.15.8",
      "3.16.5",
      "3.17.3"
    ],
    "ubuntu" => [
      "jammy-20230126",
      "focal-20230126",
      "bionic-20230126",
      "xenial-20210804",
      "trusty-20191217"
    ],
    "debian" => [
      "bullseye-20230227",
      "bullseye-20230227-slim",
      "buster-20230227",
      "buster-20230227-slim"
    ]
  }

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

    @builds
    |> Stream.flat_map(fn {os, os_versions} ->
      Stream.map(os_versions, fn os_version -> {os, os_version} end)
    end)
    |> Stream.flat_map(fn {os, os_version} ->
      Stream.map(refs, fn ref -> {os, os_version, ref} end)
    end)
    |> Stream.filter(fn {os, _os_version, ref} ->
      build_erlang_ref?(os, ref)
    end)
    |> Stream.filter(fn {os, os_version, ref} ->
      build_erlang_ref?(os, os_version, ref)
    end)
    |> Stream.flat_map(fn {os, os_version, ref} ->
      Stream.map(@archs, fn arch -> {os, os_version, ref, arch} end)
    end)
    |> Stream.filter(fn {os, os_version, ref, arch} ->
      build_erlang_ref?(arch, os, os_version, ref)
    end)
    |> Stream.map(fn {os, os_version, ref, arch} ->
      "OTP-" <> erlang = ref
      key = {erlang, os, os_diff(os, os_version), arch}
      value = {erlang, os, os_version, arch}
      {key, value}
    end)
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
  defp build_erlang_ref?("debian", "buster-" <> _, "OTP-1" <> _), do: false
  defp build_erlang_ref?("debian", "bullseye-" <> _, "OTP-1" <> _), do: false
  defp build_erlang_ref?("ubuntu", "focal-" <> _, "OTP-1" <> _), do: false

  defp build_erlang_ref?("ubuntu", "jammy-" <> _, "OTP-" <> version),
    do: build_openssl_3?(version)

  defp build_erlang_ref?(_os, _os_version, _ref), do: true

  defp build_erlang_ref?("arm64", "ubuntu", "trusty-" <> _, "OTP-17" <> _), do: false
  defp build_erlang_ref?("arm64", "ubuntu", "trusty-" <> _, "OTP-18" <> _), do: false
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
      alpine_version >= [3, 17] ->
        build_openssl_3?(erlang_version)

      alpine_version >= [3, 14] ->
        erlang_version >= [23, 2, 2]

      true ->
        true
    end
  end

  defp build_openssl_3?(erlang_version) when is_list(erlang_version) do
    erlang_version >= [24, 2]
  end

  defp build_openssl_3?(erlang_version) do
    erlang_version = parse_otp_ref(erlang_version)
    build_openssl_3?(erlang_version)
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
    |> Enum.sort(:desc)
  end

  def erlang_tags() do
    Enum.flat_map(@archs, &erlang_tags/1)
  end

  def erlang_tags(arch) do
    "hexpm/erlang-#{arch}"
    |> Bob.DockerHub.fetch_repo_tags()
    |> Stream.map(fn {tag, [^arch]} ->
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
    refs = elixir_builds()

    Stream.flat_map(@archs, fn arch ->
      Stream.flat_map(erlang_tags(arch), fn {_, {erlang, os, os_version, erlang_arch}} ->
        os_versions = @builds[os]

        if erlang_arch == arch and
             not skip_elixir_for_erlang?(erlang) and
             Enum.any?(os_versions, &(os_diff(os, os_version) == os_diff(os, &1))) do
          Stream.flat_map(refs, fn {"v" <> elixir, otp_major} ->
            if not skip_elixir?(elixir) and
                 compatible_elixir_and_erlang?(otp_major, erlang) do
              key = {elixir, erlang, os, os_diff(os, os_version), arch}
              value = {elixir, erlang, os, os_version, arch}
              [{key, value}]
            else
              []
            end
          end)
        else
          []
        end
      end)
    end)
    |> Stream.uniq_by(fn {key, _value} -> key end)
    |> Stream.map(fn {_key, value} -> {value, value} end)
  end

  defp elixir_builds() do
    "builds/elixir"
    |> Bob.Repo.fetch_built_refs()
    |> Stream.map(fn {build_name, _ref} -> build_name end)
    |> Stream.map(&split_elixir_build/1)
    |> Stream.filter(&build_elixir_ref?/1)
    |> Enum.sort(:desc)
  end

  def elixir_tags() do
    Stream.flat_map(@archs, &elixir_tags/1)
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

  defp split_elixir_build(build_name) do
    case String.split(build_name, "-otp-") do
      [elixir, major_otp] -> {elixir, major_otp}
      [elixir] -> {elixir, nil}
    end
  end

  defp build_elixir_ref?({"v0." <> _, _major_otp}), do: false
  defp build_elixir_ref?({_, _major_otp = nil}), do: false

  defp build_elixir_ref?({"v" <> version, _major_otp}) do
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

    Stream.flat_map(expected, fn {key, value} ->
      if MapSet.member?(current, key) do
        []
      else
        [value]
      end
    end)
  end

  defp compatible_elixir_and_erlang?(otp_major, erlang) do
    String.starts_with?(erlang, otp_major <> ".")
  end

  defp skip_elixir_for_erlang?(_erlang = "17." <> _), do: true
  defp skip_elixir_for_erlang?(_erlang = "18." <> _), do: true
  defp skip_elixir_for_erlang?(_erlang = "19." <> _), do: true
  defp skip_elixir_for_erlang?(_erlang), do: false

  defp skip_elixir?(elixir) do
    Version.compare(elixir, "1.10.0-0") == :lt
  end

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

  defp os_diff("ubuntu", version) do
    [version, _] = String.split(version, "-", parts: 2)
    version
  end

  defp os_diff("debian", version) do
    case String.split(version, "-", parts: 3) do
      [version, _, "slim"] -> {"slim", version}
      [version, _] -> {"debian", version}
    end
  end
end
