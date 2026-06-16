defmodule Bob.RunnerTest do
  # async: false — these tests start a named Bob.Runner and the agent block stops
  # the shared Bob.Repo, so they must not run alongside anything else.
  use ExUnit.Case, async: false

  defmodule QuietJob do
    def run(), do: :ok
    def priority(), do: 1
    def weight(), do: 1
    def concurrency(), do: :shared
  end

  defmodule BlockingJob do
    def run(), do: Process.sleep(:infinity)
    def priority(), do: 1
    def weight(), do: 1
    def concurrency(), do: :shared
  end

  setup do
    on_exit(fn ->
      case Process.whereis(Bob.Runner) do
        nil -> :ok
        pid -> Process.exit(pid, :kill)
      end
    end)

    :ok
  end

  describe "master node" do
    setup do
      owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Bob.Repo, shared: true)
      on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)

      previous = Application.get_env(:bob, :local_jobs)
      Application.put_env(:bob, :local_jobs, [QuietJob])
      on_exit(fn -> Application.put_env(:bob, :local_jobs, previous) end)

      :ok
    end

    test "claims a queued job from the local (repo-backed) queue" do
      Bob.Queue.add(QuietJob, [])

      {:ok, runner} = Bob.Runner.start_link([])
      send(runner, :local_timeout)
      # Flush the mailbox so the :local_timeout tick has been processed.
      :sys.get_state(runner)

      assert Bob.Queue.start(QuietJob) == :error
    end

    test "shutdown requeues in-flight jobs" do
      # The runner exits with :shutdown, which would propagate over the
      # start_link link and kill the test.
      Process.flag(:trap_exit, true)

      previous = Application.get_env(:bob, :local_jobs)
      Application.put_env(:bob, :local_jobs, [BlockingJob])
      on_exit(fn -> Application.put_env(:bob, :local_jobs, previous) end)

      Bob.Queue.add(BlockingJob, [])

      {:ok, runner} = Bob.Runner.start_link([])
      send(runner, :local_timeout)
      :sys.get_state(runner)

      # The job is claimed and its task is blocked inside run/0.
      assert Bob.Queue.start(BlockingJob) == :error
      [%{state: "running"} = job] = Bob.Queue.running()

      :ok = GenServer.stop(runner, :shutdown)

      assert Bob.Repo.get!(Bob.Queue.Job, job.id).state == "queued"
    end

    test "shutdown kills the in-flight task before requeueing" do
      task = Task.Supervisor.async_nolink(Bob.Tasks, fn -> Process.sleep(:infinity) end)

      Bob.Queue.add(QuietJob, [:terminate_test])
      {:ok, {id, [:terminate_test]}} = Bob.Queue.start(QuietJob)

      timer = Process.send_after(self(), :noop, 100_000)

      state = %{
        tasks: %{task.ref => {QuietJob, [:terminate_test], {:local, id}, task.pid, timer}}
      }

      Bob.Runner.terminate(:shutdown, state)

      refute Process.alive?(task.pid)
      assert Bob.Repo.get!(Bob.Queue.Job, id).state == "queued"
    end

    test "an abnormal task exit marks the job failed" do
      Bob.Queue.add(QuietJob, [:down_test])
      {:ok, {id, [:down_test]}} = Bob.Queue.start(QuietJob)

      ref = make_ref()
      timer = Process.send_after(self(), :noop, 100_000)
      state = %{tasks: %{ref => {QuietJob, [:down_test], {:local, id}, self(), timer}}}

      {:noreply, new_state} =
        Bob.Runner.handle_info({:DOWN, ref, :process, self(), :killed}, state)

      assert new_state.tasks == %{}
      assert Bob.Repo.get!(Bob.Queue.Job, id).state == "failed"
    end

    test "a task that outlives its timeout is killed and the job failed" do
      task = Task.Supervisor.async_nolink(Bob.Tasks, fn -> Process.sleep(:infinity) end)

      Bob.Queue.add(QuietJob, [:timeout_test])
      {:ok, {id, [:timeout_test]}} = Bob.Queue.start(QuietJob)

      timer = Process.send_after(self(), :noop, 100_000)
      state = %{tasks: %{task.ref => {QuietJob, [:timeout_test], {:local, id}, task.pid, timer}}}

      {:noreply, new_state} = Bob.Runner.handle_info({:job_timeout, task.ref}, state)

      refute Process.alive?(task.pid)
      assert new_state.tasks == %{}
      assert Bob.Repo.get!(Bob.Queue.Job, id).state == "failed"
    end
  end

  describe "agent node (no repo)" do
    setup do
      previous = %{
        master?: Application.get_env(:bob, :master?),
        local_jobs: Application.get_env(:bob, :local_jobs),
        remote_jobs: Application.get_env(:bob, :remote_jobs)
      }

      # Mimic an agent: Bob.Repo is never started there, so take it down here. A
      # non-empty local_jobs makes the regression observable — the old code polled
      # the local queue, which would reach the stopped repo and crash.
      :ok = Supervisor.terminate_child(Bob.Supervisor, Bob.Repo)
      Application.put_env(:bob, :master?, false)
      Application.put_env(:bob, :local_jobs, [QuietJob])
      Application.put_env(:bob, :remote_jobs, [])

      on_exit(fn ->
        {:ok, _} = Supervisor.restart_child(Bob.Supervisor, Bob.Repo)
        Ecto.Adapters.SQL.Sandbox.mode(Bob.Repo, :manual)
        Application.put_env(:bob, :master?, previous.master?)
        Application.put_env(:bob, :local_jobs, previous.local_jobs)
        Application.put_env(:bob, :remote_jobs, previous.remote_jobs)
      end)

      :ok
    end

    test "the database really is unavailable (test premise)" do
      assert_raise RuntimeError, ~r/could not lookup Ecto repo/, fn ->
        Bob.Queue.queue_sizes()
      end
    end

    test "polls for work on startup without touching the database" do
      Process.flag(:trap_exit, true)

      {:ok, runner} = Bob.Runner.start_link([])

      # init/1 drives the agent poll loop. With the regression it also polled the
      # local queue, crashing on the stopped repo and exiting the linked runner.
      refute_receive {:EXIT, ^runner, _reason}, 200
      assert Process.alive?(runner)
    end

    test "re-polls after a job completes without touching the database" do
      Process.flag(:trap_exit, true)

      {:ok, runner} = Bob.Runner.start_link([])
      assert Bob.Runner.run(QuietJob, []) == :ok

      # Completing a job triggers another poll; on an agent that must stay off the
      # local (repo-backed) queue.
      refute_receive {:EXIT, ^runner, _reason}, 300
      assert Process.alive?(runner)
    end
  end
end
