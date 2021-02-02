defmodule Bob.DockerHub.Cache do
  use GenServer

  @timeout 5 * 60_000

  def start_link([]) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init([]) do
    :ets.new(__MODULE__, [:ordered_set, :public, :named_table])
    {:ok, %{waiting: %{}, locks: %{}}}
  end

  def handle_call({:lock, repo}, {pid, _tag} = from, state) do
    case Map.fetch(state.waiting, repo) do
      {:ok, waiters} ->
        state = %{state | waiting: Map.put(state.waiting, repo, [from | waiters])}
        {:noreply, state}

      :error ->
        monitor_ref = Process.monitor(pid)
        timer_ref = Process.send_after(self(), {:timeout, repo, monitor_ref}, @timeout)

        state = %{
          state
          | waiting: Map.put(state.waiting, repo, []),
            locks: Map.put(state.locks, repo, {timer_ref, monitor_ref})
        }

        {:reply, :aquired, state}
    end
  end

  def handle_call({:unlock, repo}, _from, state) do
    case Map.fetch(state.locks, repo) do
      {:ok, {timer_ref, monitor_ref}} ->
        Enum.each(Map.fetch!(state.waiting, repo), &GenServer.reply(&1, :done))
        Process.demonitor(monitor_ref)
        Process.cancel_timer(timer_ref)

      :error ->
        :ok
    end

    state = %{
      state
      | waiting: Map.delete(state.waiting, repo),
        locks: Map.delete(state.locks, repo)
    }

    {:reply, :ok, state}
  end

  def handle_info({:timeout, repo, monitor_ref}, state) do
    {:noreply, remove_lock(repo, monitor_ref, state)}
  end

  def handle_info({:DOWN, ref, :process, _object, _reason}, state) do
    case Enum.find(state.locks, fn {_repo, {_timer_ref, monitor_ref}} -> ref == monitor_ref end) do
      {repo, {_timer_ref, monitor_ref}} ->
        {:noreply, remove_lock(repo, monitor_ref, state)}

      nil ->
        {:noreply, state}
    end
  end

  defp remove_lock(repo, monitor_ref, state) do
    case Map.fetch(state.locks, repo) do
      {:ok, {_timer_ref, ^monitor_ref}} ->
        Process.demonitor(monitor_ref)
        Enum.each(Map.fetch!(state.waiting, repo), &GenServer.reply(&1, :done))

      _ ->
        :ok
    end

    %{
      state
      | waiting: Map.delete(state.waiting, repo),
        locks: Map.delete(state.locks, repo)
    }
  end

  def add(repo, tag, archs) do
    :ets.insert(__MODULE__, {{:data, repo, {tag, archs}}, true})
  end

  def lookup(repo, fun) do
    case :ets.lookup(__MODULE__, {:status, repo}) do
      [] ->
        try do
          case GenServer.call(__MODULE__, {:lock, repo}, @timeout * 2) do
            :aquired ->
              result = fun.()

              :ets.insert(__MODULE__, Enum.map(fun.(), &{{:data, repo, &1}, true}))
              :ets.insert(__MODULE__, {{:status, repo}, true})

              result

            :done ->
              lookup(repo, fun)
          end
        after
          GenServer.call(__MODULE__, {:unlock, repo})
        end

      [{_, true}] ->
        :ets.select(__MODULE__, [{{{:data, repo, :"$1"}, true}, [], [:"$1"]}])
    end
  end
end
