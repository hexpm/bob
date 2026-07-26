defmodule Bob.PromEx.Plugins.Bob do
  @moduledoc """
  PromEx plugin for Bob's build queue and runner.

  Event metrics are emitted by `Bob.Runner` on every node. Queue depth is
  polled from Postgres, so that polling group only runs on the master.
  """

  use PromEx.Plugin

  @impl true
  def event_metrics(_opts) do
    Event.build(:bob_job_event_metrics, [
      distribution("bob.job.run.duration.milliseconds",
        event_name: [:bob, :job, :stop],
        measurement: :duration,
        unit: {:native, :millisecond},
        description: "Build job duration.",
        reporter_options: [
          buckets: [
            1_000,
            5_000,
            15_000,
            60_000,
            300_000,
            900_000,
            1_800_000,
            3_600_000,
            7_200_000
          ]
        ],
        tags: [:job_type, :result],
        tag_values: &job_stop_tag_values/1
      ),
      counter("bob.job.timeout.total",
        event_name: [:bob, :job, :timeout],
        description: "Build jobs killed after exceeding the job timeout.",
        tags: [:job_type],
        tag_values: &job_tag_values/1
      ),
      counter("bob.job.crash.total",
        event_name: [:bob, :job, :crash],
        description: "Build jobs that died from an uncaught throw or exit.",
        tags: [:job_type],
        tag_values: &job_tag_values/1
      )
    ])
  end

  @impl true
  def polling_metrics(opts) do
    poll_rate = Keyword.get(opts, :poll_rate, 15_000)

    [runner_metrics(poll_rate)] ++
      if Application.get_env(:bob, :master?) do
        [queue_metrics(poll_rate)]
      else
        []
      end
  end

  defp runner_metrics(poll_rate) do
    Polling.build(
      :bob_runner_polling_metrics,
      poll_rate,
      {__MODULE__, :execute_runner_metrics, []},
      [
        last_value("bob.runner.tasks.count",
          event_name: [:bob, :runner, :tasks],
          measurement: :count,
          description: "Number of build jobs currently running on this node."
        )
      ]
    )
  end

  defp queue_metrics(poll_rate) do
    Polling.build(
      :bob_queue_polling_metrics,
      poll_rate,
      {__MODULE__, :execute_queue_metrics, []},
      [
        last_value("bob.queue.size.count",
          event_name: [:bob, :queue, :size],
          measurement: :count,
          description: "Number of queued build jobs.",
          tags: [:job_type],
          tag_values: &job_tag_values/1
        )
      ]
    )
  end

  @doc false
  def execute_runner_metrics() do
    if GenServer.whereis(Bob.Runner) do
      %{tasks: tasks} = Bob.Runner.state()
      :telemetry.execute([:bob, :runner, :tasks], %{count: map_size(tasks)}, %{})
    end

    :ok
  end

  @doc false
  def execute_queue_metrics() do
    sizes = Map.new(Bob.Queue.queue_sizes())

    known_keys =
      Application.get_env(:bob, :local_jobs, []) ++ Application.get_env(:bob, :remote_jobs, [])

    # Emit zeroes for configured but empty queues so gauges don't go stale
    for key <- Enum.uniq(known_keys ++ Map.keys(sizes)) do
      :telemetry.execute([:bob, :queue, :size], %{count: Map.get(sizes, key, 0)}, %{key: key})
    end

    :ok
  rescue
    # Polling must not crash while the Repo is unavailable (e.g. while it is
    # restarting); ArgumentError covers the repo not yet being registered
    DBConnection.ConnectionError -> :ok
    ArgumentError -> :ok
  end

  defp job_stop_tag_values(%{key: key, result: result}) do
    %{job_type: job_label(key), result: result}
  end

  defp job_tag_values(%{key: key}) do
    %{job_type: job_label(key)}
  end

  @doc """
  Formats a queue module key (`Bob.Job.BuildOTP` or `{Bob.Job.BuildOTP, "amd64"}`)
  as a low-cardinality metric label like `"BuildOTP-amd64"`.
  """
  def job_label({module, key}), do: "#{job_label(module)}-#{key}"
  def job_label(module) when is_atom(module), do: module |> Module.split() |> List.last()
end
