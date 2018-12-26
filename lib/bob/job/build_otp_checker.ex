defmodule Bob.Job.BuildOTPChecker do
  @repo "erlang/otp"
  @linux "ubuntu-14.04"
  @build_path "builds/otp/#{@linux}"

  def run([]) do
    for {ref_name, ref} <- Bob.GitHub.diff(@repo, @build_path),
        build_ref?(ref_name),
        do: Bob.Queue.run(Bob.Job.BuildOTP, [ref_name, ref, @linux])
  end

  def equal?(_, _), do: true

  def similar?(_, _), do: true

  defp build_ref?("OTP-18.0-rc2"), do: false
  defp build_ref?("OTP_" <> _), do: false
  defp build_ref?("OTP-" <> _), do: true
  defp build_ref?("maint-r" <> _), do: false
  defp build_ref?("maint" <> _), do: true
  defp build_ref?("master" <> _), do: true
  defp build_ref?(_), do: false
end
