defmodule Bob.Job.BuildOTPChecker do
  @repo "erlang/otp"
  @linux "ubuntu-14.04"
  @build_path "builds/otp/#{@linux}"

  def run([type]) do
    for {ref_name, ref} <- Bob.GitHub.diff(@repo, @build_path),
        build_ref?(type, ref_name),
        do: Bob.Queue.run(Bob.Job.BuildOTP, [ref_name, ref, @linux])
  end

  def equal?(_, _), do: true

  def similar?(_, _), do: true

  defp build_ref?(_type, "OTP-18.0-rc2"), do: false
  defp build_ref?(_type, "OTP_" <> _), do: false
  defp build_ref?(_type, "maint-r" <> _), do: false
  defp build_ref?(:tags, "OTP-" <> _), do: true
  defp build_ref?(:branches, "maint" <> _), do: true
  defp build_ref?(:branches, "master" <> _), do: true
  defp build_ref?(_type, _ref), do: false
end
