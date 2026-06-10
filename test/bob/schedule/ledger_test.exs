defmodule Bob.Schedule.LedgerTest do
  use Bob.DataCase

  alias Bob.Schedule.Ledger

  defmodule TestJob do
  end

  @period {15, :min}
  @period_seconds 15 * 60

  test "claims the first tick" do
    assert Ledger.claim(TestJob, [], @period)
  end

  test "rejects further claims within the period" do
    now = DateTime.utc_now()

    assert Ledger.claim(TestJob, [], @period, now)
    refute Ledger.claim(TestJob, [], @period, now)
    refute Ledger.claim(TestJob, [], @period, DateTime.add(now, 60, :second))
    refute Ledger.claim(TestJob, [], @period, DateTime.add(now, div(@period_seconds, 2), :second))
  end

  test "claims again once the period has elapsed" do
    now = DateTime.utc_now()

    assert Ledger.claim(TestJob, [], @period, now)
    assert Ledger.claim(TestJob, [], @period, DateTime.add(now, @period_seconds, :second))
  end

  test "accepts claims slightly early to absorb timer drift" do
    now = DateTime.utc_now()

    assert Ledger.claim(TestJob, [], @period, now)
    assert Ledger.claim(TestJob, [], @period, DateTime.add(now, @period_seconds - 30, :second))
  end

  test "claims are independent per args" do
    now = DateTime.utc_now()

    assert Ledger.claim(TestJob, [:a], @period, now)
    assert Ledger.claim(TestJob, [:b], @period, now)
    refute Ledger.claim(TestJob, [:a], @period, now)
  end

  test "claims are independent per module" do
    now = DateTime.utc_now()

    assert Ledger.claim(TestJob, [], @period, now)
    assert Ledger.claim(Bob.Job.OTPChecker, [], @period, now)
  end

  test "supports bare atom periods" do
    now = DateTime.utc_now()

    assert Ledger.claim(TestJob, [], :day, now)
    refute Ledger.claim(TestJob, [], :day, DateTime.add(now, 12 * 60 * 60, :second))
    assert Ledger.claim(TestJob, [], :day, DateTime.add(now, 24 * 60 * 60, :second))
  end
end
