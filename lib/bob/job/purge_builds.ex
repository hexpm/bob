defmodule Bob.Job.PurgeBuilds do
  def run(keys) do
    Bob.Fastly.purge_builds(keys)
  end

  def priority(), do: 1
  def weight(), do: 1
  def concurrency(), do: :shared
end
