defmodule Bob.Schedule do
  use GenServer

  @seconds_min 60
  @seconds_hour 60 * 60
  @seconds_day 60 * 60 * 24

  def start_link([schedule]) do
    GenServer.start_link(__MODULE__, [schedule], name: __MODULE__)
  end

  def init([schedule]) do
    Enum.each(schedule, fn opts ->
      time =
        if opts[:time] do
          calc_when(opts[:time], opts[:period]) * 1000
        else
          0
        end

      message =
        {:run, opts[:module], opts[:args], opts[:time], opts[:period],
         Keyword.get(opts, :queue, true), Keyword.get(opts, :log, true)}

      Process.send_after(self(), message, time)
    end)

    {:ok, []}
  end

  def handle_info({:run, module, args, time, period, queue?, log?} = message, _) do
    if queue? do
      Bob.Queue.add(module, args || [])
    else
      Bob.Runner.run(module, args || [], fn -> :ok end, fn -> :ok end, log: log?)
    end

    time = calc_when(time, period) * 1000
    Process.send_after(self(), message, time)
    {:noreply, []}
  end

  defp calc_when(nil, period) do
    calc_period(period)
  end

  defp calc_when(time, period) when period in [:day, :hour, :min] do
    # TODO: NaiveDateTime
    {_, now} = :calendar.local_time()
    now = time_to_seconds(period, now)
    time = time_to_seconds(period, time)
    diff = time - now

    if diff <= 0 do
      calc_period({1, period}) + diff
    else
      diff
    end
  end

  defp calc_period({num, :day}), do: num * @seconds_day
  defp calc_period({num, :hour}), do: num * @seconds_hour
  defp calc_period({num, :min}), do: num * @seconds_min
  defp calc_period({num, :sec}), do: num

  defp time_to_seconds(:day, {hour, min, sec}),
    do: @seconds_hour * hour + @seconds_min * min + sec

  defp time_to_seconds(:hour, {_hour, min, sec}), do: @seconds_min * min + sec
  defp time_to_seconds(:hour, {min, sec}), do: @seconds_min * min + sec
  defp time_to_seconds(:min, {_hour, _min, sec}), do: sec
  defp time_to_seconds(:min, sec), do: sec
end
