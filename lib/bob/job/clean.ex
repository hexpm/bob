defmodule Bob.Job.Clean do
  require Logger

  def run([]) do
    Bob.Script.run({:script, "clean.sh"}, [], "/tmp")
  end

  def equal?(_, _), do: false
  def similar?(_, _), do: true
end
