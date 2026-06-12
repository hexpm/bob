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
    requests()
    manifest()
  end

  def run(:erlang), do: erlang()
  def run(:elixir), do: elixir()
  def run(:requests), do: requests()
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
    refs = latest_erlang_refs(erlang_refs())

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

  def archs(), do: @archs

  def erlang_versions() do
    Enum.map(erlang_refs(), fn "OTP-" <> version -> version end)
  end

  # Whether the build rules allow this erlang/os/os_version combination on all archs.
  def valid_erlang_build?(erlang, os, os_version) do
    ref = "OTP-" <> erlang

    build_erlang_ref?(os, ref) and build_erlang_ref?(os, os_version, ref) and
      Enum.all?(@archs, &build_erlang_ref?(&1, os, os_version, ref))
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
    |> github().fetch_repo_refs()
    |> Enum.map(fn {ref_name, _ref} -> ref_name end)
    |> Enum.filter(&String.starts_with?(&1, "OTP-"))
    |> Enum.sort(&(cmp_erlang_tags(&1, &2) != :lt))
  end

  defp github(), do: Application.get_env(:bob, :github, Bob.GitHub)

  # Keeps only the newest ref per OTP major.minor line. Stable releases rank
  # above prereleases within a line, so RCs drop out once a stable lands.
  # Selection happens before the per-OS filters: a line whose newest ref an OS
  # rule rejects gets no older fallback.
  def latest_erlang_refs(refs) do
    refs
    |> Enum.sort(&(cmp_erlang_tags(&1, &2) != :lt))
    |> Enum.uniq_by(fn "OTP-" <> version ->
      version |> to_matchable() |> elem(0) |> Enum.take(2)
    end)
  end

  defp latest_erlang_versions() do
    erlang_refs()
    |> latest_erlang_refs()
    |> MapSet.new(fn "OTP-" <> version -> version end)
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
    refs = latest_elixir_builds(elixir_builds())
    latest_erlang = latest_erlang_versions()

    Stream.flat_map(current_erlang_tags(builds), fn {erlang, os, os_version, erlang_arch} ->
      if MapSet.member?(latest_erlang, erlang) and not skip_elixir_for_erlang?(erlang) and
           os_version in builds[os] do
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

  # Whether the build rules allow this elixir build on this exact erlang/os/os_version.
  def valid_elixir_build?(elixir, otp_major, erlang, os, os_version) do
    build_elixir_ref?({"v" <> elixir, otp_major}) and not skip_elixir?(elixir) and
      not skip_elixir_for_erlang?(erlang) and compatible_elixir_and_erlang?(otp_major, erlang) and
      valid_erlang_build?(erlang, os, os_version)
  end

  # Keeps only the newest build per {elixir major.minor, otp major} pair.
  # Stable releases rank above prereleases within a pair.
  def latest_elixir_builds(builds) do
    builds
    |> Enum.sort(&cmp_elixir_tags/2)
    |> Enum.uniq_by(fn {"v" <> elixir, otp} ->
      version = Version.parse!(normalize_version(elixir))
      {version.major, version.minor, otp}
    end)
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

  # Requests that still have no tags after this long are unbuildable; expiring
  # them stops the reconciliation from re-enqueueing doomed jobs forever.
  @request_ttl_days 14

  # User-requested builds are one-time: pinned to the os_version current at
  # request time and reconciled here until every target tag exists. Requests
  # whose os_version rotated out of builds() expire instead.
  def requests() do
    builds = builds()

    Enum.each(Bob.BuildRequests.pending(), fn request ->
      cond do
        request.os_version not in Map.get(builds, request.os, []) ->
          Bob.BuildRequests.expire(request)

        DateTime.diff(DateTime.utc_now(), request.inserted_at, :day) >= @request_ttl_days ->
          Bob.BuildRequests.expire(request)

        true ->
          case request_jobs(request) do
            [] -> Bob.BuildRequests.complete(request)
            jobs -> Bob.Queue.add_many(jobs)
          end
      end
    end)
  end

  def request_jobs(%{kind: "erlang"} = request) do
    %{erlang: erlang, os: os, os_version: os_version} = request
    tag = "#{erlang}-#{os}-#{os_version}"

    Enum.flat_map(@archs, fn arch ->
      if tag_present?("hexpm/erlang-#{arch}", tag) do
        []
      else
        [{{Bob.Job.BuildDockerErlang, arch}, [erlang, os, os_version]}]
      end
    end)
  end

  # The elixir image is built FROM the erlang image, and failed jobs are not
  # retried by the queue, so the elixir job is only enqueued once its base tag
  # exists; until then the erlang build is enqueued and the next reconciliation
  # cycle picks the request up again.
  def request_jobs(%{kind: "elixir"} = request) do
    %{elixir: elixir, erlang: erlang, os: os, os_version: os_version} = request
    erlang_tag = "#{erlang}-#{os}-#{os_version}"
    elixir_tag = "#{elixir}-erlang-#{erlang}-#{os}-#{os_version}"

    Enum.flat_map(@archs, fn arch ->
      cond do
        tag_present?("hexpm/elixir-#{arch}", elixir_tag) ->
          []

        tag_present?("hexpm/erlang-#{arch}", erlang_tag) ->
          [{{Bob.Job.BuildDockerElixir, arch}, [elixir, erlang, os, os_version]}]

        true ->
          [{{Bob.Job.BuildDockerErlang, arch}, [erlang, os, os_version]}]
      end
    end)
  end

  defp tag_present?(repo, tag) do
    repo
    |> Bob.Artifacts.docker_tags_present([tag])
    |> MapSet.member?(tag)
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
