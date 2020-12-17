defmodule Bob.DockerHub.Cache do
  use GenServer

  @timeout 5 * 60_000

  def start_link([]) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init([]) do
    :ets.new(__MODULE__, [:ordered_set, :public, :named_table])
    {:ok, %{}}
  end

  def handle_call({:lock, repo}, from, locks) do
    case Map.fetch(locks, repo) do
      {:ok, waiting} -> {:noreply, Map.put(locks, repo, [from | waiting])}
      :error -> {:reply, :aquired, Map.put(locks, repo, [])}
    end
  end

  def handle_call({:unlock, repo}, _from, locks) do
    Enum.each(Map.fetch!(locks, repo), &GenServer.reply(&1, :done))
    {:reply, :ok, Map.delete(locks, repo)}
  end

  def add(repo, tag) do
    :ets.insert(__MODULE__, {{:data, repo, tag}, true})
  end

  def lookup(repo, fun) do
    case :ets.lookup(__MODULE__, {:status, repo}) do
      [] ->
        case GenServer.call(__MODULE__, {:lock, repo}, @timeout) do
          :aquired ->
            result = fun.()

            :ets.insert(__MODULE__, Enum.map(fun.(), &{{:data, repo, &1}, true}))
            :ets.insert(__MODULE__, {{:status, repo}, true})
            GenServer.call(__MODULE__, {:unlock, repo})

            result

          :done ->
            lookup(repo, fun)
        end

      [{_, true}] ->
        :ets.select(__MODULE__, [{{{:data, repo, :"$1"}, true}, [], [:"$1"]}])
    end
  end
end
