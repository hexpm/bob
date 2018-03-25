defmodule Bob.Periodic do
  use GenServer

  @seconds_min  60
  @seconds_hour 60 * 60
  @seconds_day  60 * 60 * 24

  def start_link() do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init([]) do
    env = Application.get_env(:bob, :periodic)

    Enum.each(env, fn {name, key} ->
      opts = Application.get_env(:bob, name)[key]

      ms = calc_when(opts[:time], opts[:period]) * 1000
      dir = opts[:dir] || :temp
      :erlang.send_after(ms, self(), {:task, name, opts[:time], opts[:period], opts[:action], dir})
    end)

    {:ok, []}
  end

  def handle_info({:task, name, time, period, action, dir}, _) do
    ms = calc_when(time, period) * 1000
    :erlang.send_after(ms, self(), {:task, name, time, period, action, dir})

    Bob.Queue.run(name, :period, action, [], dir)
    {:noreply, []}
  end

  defp calc_when(nil, period) do
    calc_period(period)
  end

  defp calc_when(time, period) when period in [:day, :hour, :min] do
    {_, now} = :calendar.local_time()
    now = time_to_seconds(period, now)
    time = time_to_seconds(period, time)
    diff = time - now

    if diff < 0 do
      calc_period({1, period}) + diff
    else
      diff
    end
  end

  defp calc_period({num, :day}), do: num * @seconds_day
  defp calc_period({num, :hour}), do: num * @seconds_hour
  defp calc_period({num, :min}), do: num * @seconds_min

  defp time_to_seconds(:day, {hour, min, sec}), do: @seconds_hour * hour + @seconds_min * min + sec
  defp time_to_seconds(:hour, {_hour, min, sec}), do: @seconds_min * min + sec
  defp time_to_seconds(:hour, {min, sec}), do: @seconds_min * min + sec
  defp time_to_seconds(:min, {_hour, _min, sec}), do: sec
  defp time_to_seconds(:min, sec), do: sec
end
