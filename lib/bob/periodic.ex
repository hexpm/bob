defmodule Bob.Periodic do  use GenServer
  def start_link do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @seconds_day 24 * 60 * 60
  @seconds_hour 60 * 60
  @seconds_min 60

  def init([]) do
    repos = Application.get_env(:bob, :repos)

    Enum.each(repos, fn {full_name, repo} ->
      Enum.each(repo.on.time, fn {time, {_, ref, jobs}} ->
        ms = calc_when(time) * 1000
        :erlang.send_after(ms, self, {:task, full_name, time, ref, jobs})
      end)
    end)

    {:ok, []}
  end

  def handle_info({:task, full_name, time, ref, jobs}, _) do
    repos = Application.get_env(:bob, :repos)
    repo = repos[full_name]

    {secs, _, _} = repo.on.time[time]
    ms = secs * 1000
    :erlang.send_after(ms, self, {:task, full_name, time, ref, jobs})

    Bob.Queue.build(repo, full_name, ref, jobs)
    {:noreply, []}
  end

  defp calc_when(time) do
    {_, now} = :calendar.local_time
    now = time_to_seconds(now)
    time = time_to_seconds(time)
    diff = time - now

    if diff < 0 do
      diff = @seconds_day + diff
    end

    diff
  end

  defp time_to_seconds({hour, min, sec}) do
    @seconds_hour * hour + @seconds_min * min + sec
  end
end
