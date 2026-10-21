defmodule Dawarich.Stats.ToponymsRefreshTest do
  use Dawarich.JobsCase

  alias Dawarich.State
  alias Dawarich.StatsFixtures, as: F
  alias Dawarich.Stats.{GeocodedDays, ToponymsRefresh}

  @t0 1_790_000_000
  @user 71
  @leipzig %{"city" => "Leipzig", "country_name" => "Germany"}
  @cursor "stats:toponyms_reconciliation:cursor"
  @discovery "stats:toponyms_reconciliation:missing_cursor"

  setup do
    F.reset!()
    F.user!(@user, %{"timezone" => "Etc/UTC", "min_minutes_spent_in_city" => 0})
    :ok
  end

  test "repairs at most two historical months a run and walks the statistics in id order" do
    for month <- 1..5 do
      F.point!(7100 + month, @user, F.ts(2014, month, 15), @leipzig)
      F.stat!(7110 + month, @user, 2014, month)
    end

    State.put_cursor(ScratchRepo, @cursor, "7110")

    for repaired <- [2, 4, 5] do
      assert ToponymsRefresh.run(ScratchRepo, clock: @t0) == :ok
      assert rows("SELECT count(*) FROM stats WHERE toponyms <> '[]'::jsonb") == [[repaired]]
    end
  end

  test "keeps a pending day after a failed refresh and acknowledges it when a later run succeeds" do
    F.point!(7201, @user, F.ts(2014, 6, 15), @leipzig)
    F.stat!(7202, @user, 2014, 6)
    GeocodedDays.mark(ScratchRepo, @user, F.ts(2014, 6, 15), @t0)

    failing = fn _repo, _account, _year, _month, _invalidate, _opts ->
      raise "calculation unavailable"
    end

    ExUnit.CaptureLog.capture_log(fn ->
      assert ToponymsRefresh.run(ScratchRepo, clock: @t0 + 3_660, refresh: failing) == :ok
    end)

    assert rows("SELECT toponyms FROM stats WHERE id = 7202") == [[[]]]
    assert [_pending] = GeocodedDays.due(ScratchRepo, 10, @t0 + 7_320)
    assert ToponymsRefresh.run(ScratchRepo, clock: @t0 + 7_320) == :ok
    assert [[[%{"country" => "Germany"}]]] = rows("SELECT toponyms FROM stats WHERE id = 7202")
    assert GeocodedDays.due(ScratchRepo, 10, @t0 + 7_320) == []
  end

  test "hands a pending month without statistics to a full calculation without creating its row" do
    F.point!(7301, @user, F.ts(2014, 6, 15))
    State.put_cursor(ScratchRepo, @discovery, Jason.encode!([@user + 1, 0]))
    GeocodedDays.mark(ScratchRepo, @user, F.ts(2014, 6, 15), @t0)

    assert ToponymsRefresh.run(ScratchRepo, clock: @t0 + 3_660) == :ok

    assert F.calculations() == [
             %{
               "user_id" => @user,
               "year" => 2014,
               "month" => 6,
               "notify_on_failure" => false,
               "run_at" => @t0 + 3_660
             }
           ]

    assert rows("SELECT count(*) FROM stats") == [[0]]
  end

  test "discovers a historical month whose statistics and pending day are both missing" do
    F.point!(
      7401,
      @user,
      F.ts(2014, 6, 15),
      Map.put(@leipzig, "reverse_geocoded_at", "2026-10-01T00:00:00")
    )

    State.put_cursor(ScratchRepo, @discovery, Jason.encode!([@user, 0]))

    assert ToponymsRefresh.run(ScratchRepo, clock: @t0) == :ok
    assert [%{"year" => 2014, "month" => 6, "notify_on_failure" => false}] = F.calculations()
    assert State.cursor(ScratchRepo, @discovery) == Jason.encode!([@user, F.ts(2014, 7, 1)])
  end

  test "asks once for the full calculation of a month many pending days share" do
    for day <- 1..10 do
      F.point!(7500 + day, @user, F.ts(2014, 6, day))
      GeocodedDays.mark(ScratchRepo, @user, F.ts(2014, 6, day), @t0)
    end

    State.put_cursor(ScratchRepo, @discovery, Jason.encode!([@user, 0]))
    assert ToponymsRefresh.run(ScratchRepo, clock: @t0 + 3_660) == :ok
    assert [%{"year" => 2014, "month" => 6}] = F.calculations()
  end

  test "acknowledges a pending day of a user who no longer exists" do
    GeocodedDays.mark(ScratchRepo, 999, F.ts(2014, 6, 15), @t0)
    assert ToponymsRefresh.run(ScratchRepo, clock: @t0 + 3_660) == :ok
    assert rows("SELECT count(*) FROM phoenix.stats_geocoded_days") == [[0]]
  end

  test "keeps the turn and both cursors in phoenix.cursors under their Redis names" do
    F.point!(7601, @user, F.ts(2014, 1, 15), @leipzig)
    F.stat!(7602, @user, 2014, 1)

    assert ToponymsRefresh.run(ScratchRepo, clock: @t0) == :ok

    assert rows("SELECT key, value FROM phoenix.cursors ORDER BY key") == [
             [@cursor, "7602"],
             [@discovery, Jason.encode!([@user, F.ts(2014, 2, 1)])],
             ["stats:toponyms_reconciliation:turn", "1"]
           ]
  end
end
