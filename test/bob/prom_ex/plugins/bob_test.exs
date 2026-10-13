defmodule Bob.PromEx.Plugins.BobTest do
  # These tests change the node's role and jobs in the application environment.
  use ExUnit.Case, async: false

  alias Bob.PromEx.Plugins.Bob, as: BobPlugin

  @env_keys [:master?, :local_jobs, :remote_jobs, :master_schedule, :agent_schedule]

  setup do
    previous = Map.new(@env_keys, &{&1, Application.get_env(:bob, &1)})

    on_exit(fn ->
      Enum.each(previous, fn {key, value} -> Application.put_env(:bob, key, value) end)
    end)

    Application.put_env(:bob, :local_jobs, [Bob.Job.OTPChecker, Bob.Job.DockerChecker])
    Application.put_env(:bob, :remote_jobs, [{Bob.Job.BuildOTP, "amd64"}, Bob.Job.DockerManifest])

    Application.put_env(:bob, :master_schedule, [
      [module: Bob.Job.OTPChecker, args: [:tags], period: {15, :min}, queue: true],
      [module: Bob.Job.Reconcile, period: :day, time: {1, 0, 0}, queue: true],
      [module: Bob.Job.PurgeBuilds, period: {1, :hour}]
    ])

    Application.put_env(:bob, :agent_schedule, [[module: Bob.Job.Clean, period: {1, :hour}]])

    :ok
  end

  defp attach() do
    ref =
      :telemetry_test.attach_event_handlers(self(), [[:bob, :job, :timeout], [:bob, :job, :crash]])

    on_exit(fn -> :telemetry.detach(ref) end)
    ref
  end

  defp received(ref) do
    receive do
      {event, ^ref, measurements, metadata} -> [{event, measurements, metadata} | received(ref)]
    after
      0 -> []
    end
  end

  defp zeros(keys) do
    Enum.flat_map(keys, fn key ->
      [
        {[:bob, :job, :timeout], %{count: 0}, %{key: key}},
        {[:bob, :job, :crash], %{count: 0}, %{key: key}}
      ]
    end)
  end

  test "starts the counters of the master's local and unqueued scheduled jobs at zero" do
    Application.put_env(:bob, :master?, true)
    ref = attach()

    assert BobPlugin.initialize_counters() == :ignore

    assert received(ref) ==
             zeros([Bob.Job.OTPChecker, Bob.Job.DockerChecker, Bob.Job.PurgeBuilds])
  end

  test "starts the counters of an agent's remote and unqueued scheduled jobs at zero" do
    Application.put_env(:bob, :master?, false)
    ref = attach()

    assert BobPlugin.initialize_counters() == :ignore

    assert received(ref) ==
             zeros([{Bob.Job.BuildOTP, "amd64"}, Bob.Job.DockerManifest, Bob.Job.Clean])
  end

  test "starts every response status class at zero on the master and the agents" do
    for master? <- [true, false] do
      Application.put_env(:bob, :master?, master?)
      ref = :telemetry_test.attach_event_handlers(self(), [[:bob, :http, :response]])

      assert BobPlugin.initialize_counters() == :ignore
      :telemetry.detach(ref)

      for status_class <- ~w(1xx 2xx 3xx 4xx 5xx) do
        assert_received {[:bob, :http, :response], ^ref, %{count: 0},
                         %{status_class: ^status_class}}
      end
    end
  end

  test "a zero creates the series without counting an event" do
    Application.put_env(:bob, :master?, false)
    name = :"#{__MODULE__}.Metrics"

    metrics =
      []
      |> BobPlugin.event_metrics()
      |> List.wrap()
      |> Enum.flat_map(& &1.metrics)

    start_supervised!(PromEx.Storage.Core.child_spec(name, metrics))

    BobPlugin.initialize_counters()
    scrape = PromEx.Storage.Core.scrape(name)

    assert scrape =~ ~s(bob_job_timeout_total{job_type="BuildOTP-amd64"} 0\n)
    assert scrape =~ ~s(bob_job_crash_total{job_type="Clean"} 0\n)
    assert scrape =~ ~s(bob_http_response_total{status_class="5xx"} 0\n)
    refute scrape =~ "bob_job_run_duration_milliseconds"

    :telemetry.execute([:bob, :job, :timeout], %{count: 1}, %{key: {Bob.Job.BuildOTP, "amd64"}})
    scrape = PromEx.Storage.Core.scrape(name)

    assert scrape =~ ~s(bob_job_timeout_total{job_type="BuildOTP-amd64"} 1\n)
    assert scrape =~ ~s(bob_job_crash_total{job_type="BuildOTP-amd64"} 0\n)

    :telemetry.execute([:bob, :http, :response], %{count: 1}, %{status_class: "5xx"})
    scrape = PromEx.Storage.Core.scrape(name)

    assert scrape =~ ~s(bob_http_response_total{status_class="5xx"} 1\n)
    assert scrape =~ ~s(bob_http_response_total{status_class="2xx"} 0\n)

    assert BobPlugin.count(%{count: 0}) == 0
    assert BobPlugin.count(%{duration: 10}) == 1
  end
end
