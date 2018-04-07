defmodule Bob.Job.BackupS3 do
  require Logger

  def run([]) do
    directory = "persist/backup-s3"
    Logger.info("Using directory #{directory}")
    Bob.Script.run({:script, "backup_s3.sh"}, [], directory)
  end

  def equal?(_, _), do: false

  def similar?(_, _), do: true
end
