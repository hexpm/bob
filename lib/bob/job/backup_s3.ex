defmodule Bob.Job.BackupS3 do
  require Logger

  def run([]) do
    directory = Bob.Directory.new()
    Logger.info("Using directory #{directory}")
    Bob.Script.run({:script, "backup_s3.sh"}, [], directory)
  end

  def equal?(_, _), do: true
end
