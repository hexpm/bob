defmodule Bob.Schedule.Ledger do
  @moduledoc """
  Arbitrates schedule ticks between master instances. Every master fires its
  own timers, but a tick may only be enqueued by the instance that claims it
  here first; further claims are rejected until the entry's period has elapsed
  since the last successful claim.
  """

  alias Bob.Queue.Term
  alias Bob.Repo

  @seconds_min 60
  @seconds_hour 60 * 60
  @seconds_day 60 * 60 * 24

  # Timers drift slightly between instances and across restarts, so accept
  # claims marginally before a full period has elapsed.
  @grace_max 60

  def claim(key, args, period, now \\ DateTime.utc_now()) do
    threshold = DateTime.add(now, -threshold_seconds(period), :second)

    {:ok, %{rows: rows}} =
      Repo.query(
        """
        INSERT INTO schedule_ledger (module_key, args_digest, last_run_at, inserted_at, updated_at)
        VALUES ($1, $2, $3, $3, $3)
        ON CONFLICT (module_key, args_digest)
        DO UPDATE SET last_run_at = $3, updated_at = $3
        WHERE schedule_ledger.last_run_at <= $4
        RETURNING schedule_ledger.id
        """,
        [Term.encode(key), Term.digest(args), now, threshold]
      )

    rows != []
  end

  defp threshold_seconds(period) do
    seconds = period_seconds(period)
    seconds - min(@grace_max, div(seconds, 10))
  end

  defp period_seconds({num, :day}), do: num * @seconds_day
  defp period_seconds({num, :hour}), do: num * @seconds_hour
  defp period_seconds({num, :min}), do: num * @seconds_min
  defp period_seconds({num, :sec}), do: num
  defp period_seconds(:day), do: @seconds_day
  defp period_seconds(:hour), do: @seconds_hour
  defp period_seconds(:min), do: @seconds_min
end
