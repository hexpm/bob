defmodule Bob.Job.DockerChecker do
  require Logger

  @erlang_tag_regex ~r"^(.+)-(alpine|ubuntu|debian)-(.+)$"
  @elixir_tag_regex ~r"^(.+)-erlang-(.+)-(alpine|ubuntu|debian)-(.+)$"

  @archs ["amd64", "arm64"]
  @erlang_arch_repos Enum.map(@archs, &"hexpm/erlang-#{&1}")

  def builds() do
    [
      {"alpine",
       [
         ~r/^3\.23\.\d+$/,
         ~r/^3\.22\.\d+$/,
         ~r/^3\.21\.\d+$/,
         ~r/^3\.20\.\d+$/
       ]},
      {"ubuntu",
       [
         # 26.04
         ~r/^resolute-\d{8}(\.\d)?$/,
         # 24.04
         ~r/^noble-\d{8}(\.\d)?$/,
         # 22.04
         ~r/^jammy-\d{8}$/
       ]},
      {"debian",
       [
         # 13
         ~r/^trixie-\d{8}$/,
         ~r/^trixie-\d{8}-slim$/,
         # 12
         ~r/^bookworm-\d{8}$/,
         ~r/^bookworm-\d{8}-slim$/,
         # 11
         ~r/^bullseye-\d{8}$/,
         ~r/^bullseye-\d{8}-slim$/
       ]}
    ]
    |> Map.new(fn {repo, regexes} -> {repo, tags(repo, regexes)} end)
  end

  defp tags(repo, regexes) do
    tags =
      ("library/" <> repo)
      |> Bob.Artifacts.base_image_tags()
      |> Enum.sort(&(&1 >= &2))

    regexes
    |> Enum.map(fn regex -> Enum.find(tags, &(&1 =~ regex)) end)
    |> Enum.reject(&is_nil/1)
  end

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
  def concurrency(), do: :shared

  def erlang() do
    expected_erlang_tags()
    |> Enum.group_by(fn {_erlang, _os, _os_version, arch} -> arch end)
    |> Enum.flat_map(fn {arch, expected} ->
      present =
        Bob.Artifacts.docker_tags_present(
          "hexpm/erlang-#{arch}",
          Enum.map(expected, &erlang_tag_name/1)
        )

      Enum.reject(expected, &MapSet.member?(present, erlang_tag_name(&1)))
    end)
    |> Enum.map(fn {erlang, os, os_version, arch} ->
      {{Bob.Job.BuildDockerErlang, arch}, [erlang, os, os_version]}
    end)
    |> Bob.Queue.add_many()
  end

  defp erlang_tag_name({erlang, os, os_version, _arch}), do: "#{erlang}-#{os}-#{os_version}"

  def expected_erlang_tags() do
    refs = erlang_refs()

    Stream.flat_map(builds(), fn {os, os_versions} ->
      Stream.flat_map(refs, fn ref ->
        if build_erlang_ref?(os, ref) do
          Stream.flat_map(os_versions, fn os_version ->
            if build_erlang_ref?(os, os_version, ref) do
              Stream.flat_map(@archs, fn arch ->
                if build_erlang_ref?(arch, os, os_version, ref) do
                  "OTP-" <> erlang = ref
                  [{erlang, os, os_version, arch}]
                else
                  []
                end
              end)
            else
              []
            end
          end)
        else
          []
        end
      end)
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

  defp build_erlang_ref?("debian", "trixie-" <> _, "OTP-" <> version),
    do: build_openssl_3?(version)

  defp build_erlang_ref?("debian", "bookworm-" <> _, "OTP-" <> version),
    do: build_openssl_3?(version)

  defp build_erlang_ref?("ubuntu", "jammy-" <> _, "OTP-" <> version),
    do: build_openssl_3?(version)

  defp build_erlang_ref?("ubuntu", "noble-" <> _, "OTP-" <> version),
    do: build_openssl_3?(version)

  defp build_erlang_ref?("ubuntu", "resolute-" <> _, "OTP-" <> version),
    do: build_ubuntu_26?(version)

  defp build_erlang_ref?(_os, _os_version, _ref), do: true

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

  defp build_alpine?(alpine_version, erlang_version_string) do
    alpine_version = version_to_list(alpine_version)
    erlang_version = parse_otp_ref(erlang_version_string)

    cond do
      alpine_version >= [3, 23] ->
        erlang_version >= [26] and not String.starts_with?(erlang_version_string, "26.0-rc")

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

  defp build_ubuntu_26?(erlang_version) do
    dev_version? = String.contains?(erlang_version, "-")

    # C23 compatibility (`bool` keyword)
    case parse_otp_ref(erlang_version) do
      [26, 0] ->
        not dev_version?

      version ->
        version >= [26, 0]
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
    |> Enum.filter(&String.starts_with?(&1, "OTP-"))
    |> Enum.sort(&(cmp_erlang_tags(&1, &2) != :lt))
  end

  defp cmp_erlang_tags("OTP-" <> left, "OTP-" <> right) do
    cmp_erlang_components(to_matchable(left), to_matchable(right))
  end

  defp cmp_erlang_components({[left | lefts], left_pre}, {[right | rights], right_pre}) do
    cond do
      left > right -> :gt
      left < right -> :lt
      true -> cmp_erlang_components({lefts, left_pre}, {rights, right_pre})
    end
  end

  defp cmp_erlang_components({[], left_pre}, {[], right_pre}) do
    cond do
      left_pre == [] and right_pre != [] -> :gt
      left_pre != [] and right_pre == [] -> :lt
      left_pre > right_pre -> :gt
      left_pre < right_pre -> :lt
      true -> :eq
    end
  end

  defp cmp_erlang_components({[], _left_pre}, {_rights, _right_pre}) do
    :lt
  end

  defp cmp_erlang_components({_lefts, _left_pre}, {[], _right_pre}) do
    :gt
  end

  defp to_matchable(string) do
    destructure [version, pre], String.split(string, "-", parts: 2)

    components =
      version
      |> String.split(".")
      |> Enum.map(&String.to_integer/1)

    {components, pre || []}
  end

  def elixir() do
    expected_elixir_tags()
    |> Enum.group_by(fn {_elixir, _erlang, _os, _os_version, arch} -> arch end)
    |> Enum.flat_map(fn {arch, expected} ->
      present =
        Bob.Artifacts.docker_tags_present(
          "hexpm/elixir-#{arch}",
          Enum.map(expected, &elixir_tag_name/1)
        )

      Enum.reject(expected, &MapSet.member?(present, elixir_tag_name(&1)))
    end)
    |> Enum.map(fn {elixir, erlang, os, os_version, arch} ->
      {{Bob.Job.BuildDockerElixir, arch}, [elixir, erlang, os, os_version]}
    end)
    |> Bob.Queue.add_many()
  end

  defp elixir_tag_name({elixir, erlang, os, os_version, _arch}) do
    "#{elixir}-erlang-#{erlang}-#{os}-#{os_version}"
  end

  def expected_elixir_tags() do
    builds = builds()
    refs = elixir_builds()

    Stream.flat_map(current_erlang_tags(builds), fn {erlang, os, os_version, erlang_arch} ->
      if not skip_elixir_for_erlang?(erlang) and os_version in builds[os] do
        Stream.flat_map(refs, fn {"v" <> elixir, otp_major} ->
          if compatible_elixir_and_erlang?(otp_major, erlang) do
            [{elixir, erlang, os, os_version, erlang_arch}]
          else
            []
          end
        end)
      else
        []
      end
    end)
  end

  # Erlang per-arch tags scoped to the current base-image os_versions — the
  # only ones expected_elixir_tags/0 can use. Rows returned here always carry
  # search metadata, so the tag is guaranteed to match @erlang_tag_regex.
  defp current_erlang_tags(builds) do
    os_versions = builds |> Map.values() |> List.flatten()

    @erlang_arch_repos
    |> Bob.Artifacts.erlang_tags_for_os_versions(os_versions)
    |> Enum.map(fn {"hexpm/erlang-" <> arch, tag} ->
      [erlang, os, os_version] = Regex.run(@erlang_tag_regex, tag, capture: :all_but_first)
      {erlang, os, os_version, arch}
    end)
  end

  def elixir_builds() do
    "builds/elixir"
    |> Bob.Store.fetch_built_refs()
    |> Stream.map(fn {build_name, _ref} -> build_name end)
    |> Stream.map(&split_elixir_build/1)
    |> Stream.filter(&build_elixir_ref?/1)
    |> Enum.sort(&cmp_elixir_tags/2)
    |> Enum.reject(fn {_elixir, otp} -> otp == nil end)
    |> Enum.reject(fn {"v" <> elixir, _otp} -> skip_elixir?(elixir) end)
  end

  defp split_elixir_build(build_name) do
    case String.split(build_name, "-otp-") do
      [elixir, major_otp] -> {elixir, major_otp}
      [elixir] -> {elixir, nil}
    end
  end

  defp cmp_elixir_tags({"v" <> elixir_left, otp_left}, {"v" <> elixir_right, otp_right}) do
    case Version.compare(normalize_version(elixir_left), normalize_version(elixir_right)) do
      :gt -> true
      :eq -> otp_left > otp_right
      :lt -> false
    end
  end

  defp build_elixir_ref?({"v0." <> _, _major_otp}), do: false

  defp build_elixir_ref?({"v" <> version, _major_otp}) do
    normalized_version = normalize_version(version)

    case Version.parse(normalized_version) do
      # don't build RCs for < 1.12
      {:ok, %Version{major: 1, minor: minor, pre: pre}} when minor < 12 and pre != [] -> false
      {:ok, %Version{}} -> true
      :error -> false
    end
  end

  defp build_elixir_ref?(_), do: false

  defp normalize_version(version) do
    case String.split(version, ".") do
      [major, minor] -> "#{major}.#{minor}.0"
      [_major, _minor | _rest] -> version
      _ -> version
    end
  end

  defp compatible_elixir_and_erlang?(otp_major, erlang) do
    String.starts_with?(erlang, otp_major <> ".")
  end

  defp skip_elixir_for_erlang?(_erlang = "17." <> _), do: true
  defp skip_elixir_for_erlang?(_erlang = "18." <> _), do: true
  defp skip_elixir_for_erlang?(_erlang = "19." <> _), do: true
  # Missing :code.add_pathsa/2
  defp skip_elixir_for_erlang?(_erlang = "26.0-rc1"), do: true
  defp skip_elixir_for_erlang?(_erlang), do: false

  defp skip_elixir?(elixir) do
    Version.compare(normalize_version(elixir), "1.10.0-0") == :lt
  end

  def manifest() do
    check_manifests("erlang")
    check_manifests("elixir")
  end

  # The whole per-arch vs manifest diff runs in Postgres; only mismatched tags
  # (normally none) come back, so just those few need parsing into job args.
  defp check_manifests(kind) do
    "hexpm/#{kind}"
    |> Bob.Artifacts.manifest_mismatches("hexpm/#{kind}-amd64", "hexpm/#{kind}-arm64")
    |> Enum.flat_map(fn {tag, _archs} ->
      case manifest_key(kind, tag) do
        {:ok, key} ->
          [{Bob.Job.DockerManifest, [kind, key]}]

        :error ->
          Logger.error("DOCKER CHECKER skipping unparseable #{kind} tag #{inspect(tag)}")
          []
      end
    end)
    |> Bob.Queue.add_many()
  end

  defp manifest_key("erlang", tag) do
    case Regex.run(@erlang_tag_regex, tag, capture: :all_but_first) do
      [erlang, os, os_version] -> {:ok, {erlang, os, os_version}}
      nil -> :error
    end
  end

  defp manifest_key("elixir", tag) do
    case Regex.run(@elixir_tag_regex, tag, capture: :all_but_first) do
      [elixir, erlang, os, os_version] -> {:ok, {elixir, erlang, os, os_version}}
      nil -> :error
    end
  end
end
