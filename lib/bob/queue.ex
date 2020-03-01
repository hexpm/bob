defmodule Bob.Queue do
  use GenServer
  require Logger

  def start_link([]) do
    GenServer.start_link(__MODULE__, new_state(), name: __MODULE__)
  end

  def init(state) do
    {:ok, state}
  end

  def queue(module, args) do
    GenServer.call(__MODULE__, {:queue, module, args})
  end

  def dequeue(module) do
    GenServer.call(__MODULE__, {:dequeue, module})
  end

  def state() do
    GenServer.call(__MODULE__, :state)
  end

  def handle_call({:queue, module, args}, _from, state) do
    state =
      cond do
        already_queued?(module, args, state) ->
          Logger.info("ALREADY QUEUED #{inspect(module)} #{inspect(args)}")
          state

        true ->
          Logger.info("QUEUED #{inspect(module)} #{inspect(args)}")
          update_in(state.queues[module], &((&1 || []) ++ args))
      end

    {:reply, :ok, state}
  end

  def handle_call({:dequeue, module}, _from, state) do
    case Map.get(state.queues, module, []) do
      [] ->
        {:reply, :error, state}

      [args | rest_args] ->
        {:reply, {:ok, args}, put_in(state.queue[module], rest_args)}
    end
  end

  def handle_call(:state, _from, state) do
    {:reply, state, state}
  end

  defp already_queued?(module, args, state) do
    Map.get(state.queues, module, [])
    |> Enum.any?(&module.similar?(&1, args))
  end

  defp new_state do
    %{queues: %{}}
  end
end
