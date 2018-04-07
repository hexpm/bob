defmodule Bob.Job.BuildOTP do
  require Logger

  def run([ref_name, ref, linux]) do
    directory = Bob.Directory.new()
    Logger.info("Using directory #{directory}")
    Bob.Script.run({:script, "build_otp_docker.sh"}, [ref_name, ref, linux], directory)
  end

  def equal?(args, args), do: true
  def equal?(_, _), do: false

  def similar?([ref_name, _ref1, linux], [ref_name, _ref2, linux]), do: true
  def similar?(_, _), do: false
end
