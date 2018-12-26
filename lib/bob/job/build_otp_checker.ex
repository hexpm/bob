defmodule Bob.Job.BuildOTPChecker do
  @repo "erlang/otp"
  @linux "ubuntu-14.04"
  @build_path "builds/otp/#{@linux}"

  def run([]) do
    for {ref_name, ref} <- Bob.GitHub.diff(@repo, @build_path),
        valid_ref_name?(ref_name),
        do: Bob.Queue.run(Bob.Job.BuildOTP, [ref_name, ref, @linux])
  end

  def equal?(_, _), do: true

  def similar?(_, _), do: true

  defp valid_ref_name?("OTP-18.0-rc2"), do: false
  defp valid_ref_name?("OTP_" <> _), do: false
  defp valid_ref_name?("OTP-" <> _), do: true
  defp valid_ref_name?("maint-r" <> _), do: false
  defp valid_ref_name?("maint" <> _), do: true
  defp valid_ref_name?("master" <> _), do: true
  defp valid_ref_name?(_), do: false
end
