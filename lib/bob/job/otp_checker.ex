defmodule Bob.Job.OTPChecker do
  @repo "erlang/otp"
  @linuxes ["ubuntu-14.04", "ubuntu-16.04", "ubuntu-18.04", "ubuntu-20.04", "ubuntu-22.04"]

  def run(type) do
    for linux <- @linuxes,
        {ref_name, ref} <- Bob.GitHub.diff(@repo, "builds/otp/#{linux}"),
        build_ref?(type, linux, ref_name),
        do: Bob.Queue.add(Bob.Job.BuildOTP, [ref_name, ref, linux])
  end

  def priority(), do: 1
  def weight(), do: 1

  defp build_ref?(_type, _linux, "OTP-18.0-rc2"), do: false
  defp build_ref?(_type, _linux, "maint-r" <> _), do: false
  # TODO: Delete these files
  defp build_ref?(_type, "ubuntu-20.04", "OTP-17" <> _), do: false
  defp build_ref?(_type, "ubuntu-20.04", "OTP-18" <> _), do: false
  defp build_ref?(_type, "ubuntu-20.04", "OTP-19" <> _), do: false
  defp build_ref?(_type, "ubuntu-22.04", "OTP-" <> version), do: build_openssl_3?(version)
  defp build_ref?(:tags, _linux, "OTP-" <> _), do: true
  defp build_ref?(:branches, _linux, "maint" <> _), do: true
  defp build_ref?(:branches, _linux, "master" <> _), do: true
  defp build_ref?(_type, _linux, _ref), do: false

  defp build_openssl_3?(erlang_version) do
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
