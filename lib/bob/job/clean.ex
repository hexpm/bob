defmodule Bob.Job.Clean do
  require Logger

  def run() do
    directory = Bob.Directory.new()
    Bob.Script.run({:script, "clean.sh"}, [], directory)
  end

  def priority(), do: 1
  def weight(), do: 2
  def concurrency(), do: :shared
end
