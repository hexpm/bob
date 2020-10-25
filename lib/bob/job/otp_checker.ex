defmodule Bob.Job.OTPChecker do
  @repo "erlang/otp"
  @linuxes ["ubuntu-14.04"]

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
  defp build_ref?(:tags, _linux, "OTP-" <> _), do: true
  defp build_ref?(:branches, _linux, "maint" <> _), do: true
  defp build_ref?(:branches, _linux, "master" <> _), do: true
  defp build_ref?(_type, _linux, _ref), do: false
end
