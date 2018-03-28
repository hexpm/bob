defmodule Bob.Job.BuildOTP do
  require Logger

  def run([ref_name, ref]) do
    directory = Bob.Directory.new()
    Logger.info("Using directory #{directory}")
    Bob.Script.run({:script, "build_otp_docker.sh"}, [ref_name, ref], directory)
  end

  def equal?([ref_name1, _ref1], [ref_name2, _ref2]), do: ref_name1 == ref_name2
end
