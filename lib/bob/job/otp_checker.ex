defmodule Bob.Job.OTPChecker do
  @repo "erlang/otp"
  @linuxes ["ubuntu-22.04", "ubuntu-24.04", "ubuntu-26.04"]
  @arches ["amd64", "arm64"]

  def run(_type) do
    refs = Bob.GitHub.fetch_repo_refs(@repo)

    for linux <- @linuxes,
        arch <- @arches,
        {ref_name, ref} <- unbuilt(refs, arch, linux),
        build_ref?(linux, ref_name),
        do: Bob.Queue.add({Bob.Job.BuildOTP, arch}, [ref_name, ref, linux])
  end

  def unbuilt(refs, arch, os) do
    built = Bob.Artifacts.built_otp_refs(arch, os)
    Enum.filter(refs, fn {ref_name, ref} -> Map.get(built, ref_name) != ref end)
  end

  def priority(), do: 1
  def weight(), do: 1
  def concurrency(), do: :shared

  defp build_ref?(_linux, "OTP-18.0-rc2"), do: false
  defp build_ref?(_linux, "maint-r" <> _), do: false
  defp build_ref?("ubuntu-22.04", "OTP-" <> version), do: build_ubuntu_22?(version)
  defp build_ref?("ubuntu-22.04", "maint-" <> version), do: build_ubuntu_22?(version)
  defp build_ref?("ubuntu-24.04", "OTP-" <> version), do: build_ubuntu_24?(version)
  defp build_ref?("ubuntu-24.04", "maint-" <> version), do: build_ubuntu_24?(version)
  defp build_ref?("ubuntu-26.04", "OTP-" <> version), do: build_ubuntu_26?(version)
  defp build_ref?("ubuntu-26.04", "maint-" <> version), do: build_ubuntu_26?(version)
  defp build_ref?(_linux, "OTP-" <> _), do: true
  defp build_ref?(_linux, "maint" <> _), do: true
  defp build_ref?(_linux, "master" <> _), do: true
  defp build_ref?(_linux, _ref), do: false

  defp build_ubuntu_22?(erlang_version) do
    # OpenSSL 3.0 compatibility
    erlang_version = parse_otp_ref(erlang_version)
    erlang_version >= [24, 2]
  end

  defp build_ubuntu_24?(erlang_version) do
    dev_version? = String.contains?(erlang_version, "-")

    # WX compatibility
    case parse_otp_ref(erlang_version) do
      [25, 0] ->
        not dev_version?

      version ->
        version >= [24, 3, 4]
    end
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
end
