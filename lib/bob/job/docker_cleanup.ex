defmodule Bob.Job.DockerCleanup do
  def run() do
    Bob.DockerCleanup.run()
  end

  # A live run clears the whole backlog, which takes days at Docker Hub's delete
  # rate. The next night's run is dedup'd away while this one is still going.
  def timeout(), do: 23 * 60 * 60 * 1000

  def priority(), do: 1
  def weight(), do: 1
  def concurrency(), do: :shared
end
