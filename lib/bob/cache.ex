defmodule Bob.Cache do
  @moduledoc """
  Read-through cache with per-key TTLs for values that are expensive to fetch
  (GitHub refs, S3 build lists) but fine to serve slightly stale.
  """

  use GenServer

  @table __MODULE__

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def fetch(key, ttl_seconds, fun) do
    now = System.system_time(:second)

    case :ets.lookup(@table, key) do
      [{^key, value, expires_at}] when expires_at > now ->
        value

      _ ->
        value = fun.()
        :ets.insert(@table, {key, value, now + ttl_seconds})
        value
    end
  end

  def clear() do
    :ets.delete_all_objects(@table)
    :ok
  end

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, nil}
  end
end
