defmodule Bob.Supervisor do
  use Supervisor

  def start_link do
    :supervisor.start_link(__MODULE__, [])
  end

  def init([]) do
    tree = [supervisor(Task.Supervisor, [[name: Bob.BuildSupervisor]]),
            worker(Bob.Queue, [])]
    supervise(tree, strategy: :rest_for_one)
  end
end
