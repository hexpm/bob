defmodule Bob.Job.BuildDockerElixir do
  require Logger

  def run([elixir, erlang, otp_major, os, os_version]) do
    directory = Bob.Directory.new()
    Logger.info("Using directory #{directory}")

    Bob.Script.run(
      {:script, "docker/elixir.sh"},
      [elixir, erlang, otp_major, os, os_version],
      directory
    )
  end

  def equal?(args, args), do: true
  def equal?(_, _), do: false

  def similar?(args, args), do: true
  def similar?(_, _), do: false
end
