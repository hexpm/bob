defmodule Bob.Job.BuildOTP do
  require Logger

  def run(ref_name, ref, linux, arch) do
    directory = Bob.Directory.new()
    Logger.info("Using directory #{directory}")
    Bob.Script.run({:script, "otp/otp.sh"}, [ref_name, ref, linux, arch], directory)
  end

  def priority(), do: 2
  def weight(), do: 5
  def concurrency(), do: :shared
end
