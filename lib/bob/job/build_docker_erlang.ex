defmodule Bob.Job.BuildDockerErlang do
  require Logger

  def run([ref, os, os_version]) do
    directory = Bob.Directory.new()
    Logger.info("Using directory #{directory}")
    Bob.Script.run({:script, "docker/erlang.sh"}, [ref, os, os_version], directory)
  end
end
