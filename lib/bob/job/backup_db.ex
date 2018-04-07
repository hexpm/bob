defmodule Bob.Job.BackupDB do
  require Logger

  def run([]) do
    directory = Bob.Directory.new()
    Logger.info("Using directory #{directory}")
    Bob.Script.run({:script, "backup_db.sh"}, [], directory)
  end

  def equal?(_, _), do: false

  def similar?(_, _), do: true
end
