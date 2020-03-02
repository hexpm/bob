defmodule Bob.Job.OTPChecker do
  @repo "erlang/otp"
  @linuxes ["ubuntu-14.04", "alpine-3.10"]

  def run([type]) do
    for linux <- @linuxes,
        {ref_name, ref} <- Bob.GitHub.diff(@repo, "builds/otp/#{linux}"),
        build_ref?(type, linux, ref_name),
        do: Bob.Queue.add(Bob.Job.BuildOTP, [ref_name, ref, linux])
  end

  defp build_ref?(_type, _linux, "OTP-18.0-rc2"), do: false
  defp build_ref?(_type, _linux, "maint-r" <> _), do: false
  defp build_ref?(:tags, "alpine-3.10", "OTP-17" <> _), do: false
  defp build_ref?(:tags, "alpine-3.10", "OTP-18" <> _), do: false
  defp build_ref?(:tags, _linux, "OTP-" <> _), do: true
  defp build_ref?(:branches, "alpine-3.10", "maint-17"), do: false
  defp build_ref?(:branches, "alpine-3.10", "maint-18"), do: false
  defp build_ref?(:branches, _linux, "maint" <> _), do: true
  defp build_ref?(:branches, _linux, "master" <> _), do: true
  defp build_ref?(_type, _linux, _ref), do: false
end
