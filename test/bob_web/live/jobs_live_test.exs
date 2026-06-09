defmodule BobWeb.JobsLiveTest do
  use BobWeb.ConnCase

  import Ecto.Query
  import Phoenix.LiveViewTest

  @debounce_pause 400

  test "renders running, queued, and past jobs", %{conn: conn} do
    Bob.Queue.add(Bob.Job.OTPChecker, [:queued])

    Bob.Queue.add(Bob.Job.OTPChecker, [:running])
    {:ok, _} = Bob.Queue.start(Bob.Job.OTPChecker)

    Bob.Queue.add(Bob.Job.OTPChecker, [:done])
    {:ok, {id, _}} = Bob.Queue.start(Bob.Job.OTPChecker)
    Bob.Queue.success(id)

    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "Running"
    assert html =~ "Queue"
    assert html =~ "Past"
    assert html =~ "OTPChecker"
    assert html =~ "done"
    assert html =~ ~r/Showing\s*<b>1<\/b>\s*-\s*<b>1<\/b>\s*queued\s*of\s*1 queued/
    assert html =~ ~r/Showing\s*<b>1<\/b>\s*-\s*<b>1<\/b>\s*job\s*of\s*1 job/
  end

  test "root layout links favicon assets", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ ~s(href="/favicon.ico")
    assert html =~ ~s(href="/images/favicon-64.png")
    assert html =~ ~s(href="/images/favicon-160.png")
  end

  test "refreshes when a :jobs_changed broadcast arrives", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    refute render(view) =~ ":refreshed"

    Bob.Queue.add(Bob.Job.OTPChecker, [:refreshed])
    {:ok, _} = Bob.Queue.start(Bob.Job.OTPChecker)

    # The add/start broadcasts :jobs_changed; the view reloads after the debounce window.
    Process.sleep(@debounce_pause)
    assert render(view) =~ ":refreshed"
  end

  test "ticks elapsed time for running jobs", %{conn: conn} do
    Bob.Queue.add(Bob.Job.OTPChecker, [:elapsed_tick])
    {:ok, {id, _args}} = Bob.Queue.start(Bob.Job.OTPChecker)

    started_at = DateTime.add(DateTime.utc_now(), -10, :second)

    Bob.Repo.update_all(
      from(j in Bob.Queue.Job, where: j.id == ^id),
      set: [started_at: started_at, updated_at: started_at]
    )

    {:ok, view, _html} = live(conn, ~p"/")

    Process.sleep(1600)
    assert render(view) =~ ~r/1[1-3]s/
  end
end
