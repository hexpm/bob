defmodule Bob.Job.Clean do
  require Logger

  def run([]) do
    directory = Bob.Directory.new()
    Bob.Script.run({:script, "clean.sh"}, [], directory)
  end
end
