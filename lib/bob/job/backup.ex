defmodule Bob.Job.Backup do
  require Logger

  def run([]) do
    directory = Path.join(Bob.persist_dir(), "backup")
    Logger.info("Using directory #{directory}")
    Bob.Script.run({:script, "hex/backup.sh"}, [], directory)
  end
end
