defmodule BobWeb.JobsLiveTest do
  use BobWeb.ConnCase

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
end
