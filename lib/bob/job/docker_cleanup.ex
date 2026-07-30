defmodule Bob.Job.DockerCleanup do
  def run() do
    Bob.DockerCleanup.run()
  end

  def priority(), do: 1
  def weight(), do: 1
  def concurrency(), do: :shared
end
