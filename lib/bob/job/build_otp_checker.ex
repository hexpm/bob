defmodule Bob.Job.BuildOTPChecker do
  @repo "erlang/otp"
  @linuxes ["ubuntu-14.04"]

  def run([]) do
    for linux <- @linuxes,
        {ref_name, ref} <- Bob.GitHub.diff(@repo, linux),
        do: Bob.Queue.run(Bob.Job.BuildOTP, [ref_name, ref, linux])
  end

  def equal?(_, _), do: true

  def similar?(_, _), do: true
end
