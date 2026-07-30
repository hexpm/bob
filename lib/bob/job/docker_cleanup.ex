defmodule Bob.Job.DockerCleanup do
  def run() do
    Bob.DockerCleanup.run()
  end

  # A live run clears the whole backlog, which takes days at Docker Hub's delete
  # rate. Long enough to keep going until the next night's run, which the queue
  # dedups away while this one is still running.
  def timeout(), do: 23 * 60 * 60 * 1000

  def priority(), do: 1
  def weight(), do: 1
  def concurrency(), do: :shared
end
