defmodule Bob.Job.BuildOTPChecker do
  @repo "erlang/otp"

  def run([]) do
    Enum.each(Bob.GitHub.diff(@repo), fn {ref_name, ref} ->
      Bob.Queue.run(Bob.Job.BuildOTP, [ref_name, ref])
    end)
  end

  def equal?(_, _), do: true
end
