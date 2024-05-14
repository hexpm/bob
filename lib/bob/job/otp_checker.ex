defmodule Bob.Job.OTPChecker do
  @repo "erlang/otp"
  @linuxes ["ubuntu-18.04", "ubuntu-20.04", "ubuntu-22.04"]
  @arches ["amd64", "arm64"]

  def run(_type) do
    for linux <- @linuxes,
        arch <- @arches,
        {ref_name, ref} <- Bob.GitHub.diff(@repo, "builds/otp/#{arch}/#{linux}"),
        build_ref?(linux, arch, ref_name),
        do: Bob.Queue.add({Bob.Job.BuildOTP, arch}, [ref_name, ref, linux])
  end

  def priority(), do: 1
  def weight(), do: 1
  def concurrency(), do: :shared

  defp build_ref?(_linux, _, "OTP-18.0-rc2"), do: false
  defp build_ref?(_linux, _, "maint-r" <> _), do: false
  defp build_ref?("ubuntu-18.04", "arm64", _), do: false
  defp build_ref?("ubuntu-20.04", _, "OTP-" <> version), do: build_ubuntu_20?(version)
  defp build_ref?("ubuntu-20.04", _, "maint-" <> version), do: build_ubuntu_20?(version)
  defp build_ref?("ubuntu-22.04", _, "OTP-" <> version), do: build_ubuntu_22?(version)
  defp build_ref?("ubuntu-22.04", _, "maint-" <> version), do: build_ubuntu_22?(version)
  defp build_ref?(_linux, _, "OTP-" <> _), do: true
  defp build_ref?(_linux, _, "maint" <> _), do: true
  defp build_ref?(_linux, _, "master" <> _), do: true
  defp build_ref?(_linux, _, _ref), do: false

  defp build_ubuntu_20?(erlang_version) do
    erlang_version = parse_otp_ref(erlang_version)
    erlang_version >= [20]
  end

  defp build_ubuntu_22?(erlang_version) do
    # OpenSSL 3.0 compatibility
    erlang_version = parse_otp_ref(erlang_version)
    erlang_version >= [24, 2]
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
