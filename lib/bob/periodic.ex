defmodule Bob.Periodic do
  use GenServer

  @seconds_min  60
  @seconds_hour 60 * 60
  @seconds_day  60 * 60 * 24

  def start_link do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init([]) do
    env = Application.get_env(:bob, :periodic)

    Enum.each(env, fn {name, key} ->
      opts = Application.get_env(:bob, name)[key]

      :day = opts[:period]
      ms = calc_when(opts[:time]) * 1000
      :erlang.send_after(ms, self, {:task, name, opts[:time], opts[:action]})
    end)

    {:ok, []}
  end

  def handle_info({:task, name, time, action}, _) do
    ms = @seconds_day * 1000
    :erlang.send_after(ms, self, {:task, name, time, action})

    Bob.Queue.run(name, :period, action, [])
    {:noreply, []}
  end

  defp calc_when(time) do
    {_, now} = :calendar.local_time
    now = time_to_seconds(now)
    time = time_to_seconds(time)
    diff = time - now

    if diff < 0,
      do: @seconds_day + diff,
    else: diff
  end

  defp time_to_seconds({hour, min, sec}) do
    @seconds_hour * hour + @seconds_min * min + sec
  end
end
