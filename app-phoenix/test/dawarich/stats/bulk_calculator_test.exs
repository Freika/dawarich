defmodule Dawarich.Stats.BulkCalculatorTest do
  use Dawarich.JobsCase

  alias Dawarich.StatsFixtures, as: F
  alias Dawarich.Stats.BulkCalculator

  @now ~N[2026-10-03 12:00:00.000000]
  @t0 1_790_000_000

  setup do: F.reset!()

  test "schedules the month a point falls in, in the user's zone, and marks the sweep" do
    F.user!(81, %{"timezone" => "Etc/UTC"})
    F.user!(82, %{"timezone" => "Asia/Tokyo"})
    for user <- [81, 82], do: F.point!(user * 100, user, F.ts(2020, 12, 31, 23, 30))

    for user <- [81, 82],
        do: assert(BulkCalculator.call(ScratchRepo, user, now: @now, clock: @t0) == :ok)

    assert months(81) == [[2020, 12, true]]
    assert months(82) == [[2021, 1, true]]
    assert rows("SELECT id, stats_swept_at FROM users ORDER BY id") == [[81, @now], [82, @now]]
  end

  test "a user without new points gets nothing scheduled and is still marked swept" do
    F.user!(83, %{})
    assert BulkCalculator.call(ScratchRepo, 83, now: @now) == :ok
    assert months(83) == []
    assert rows("SELECT stats_swept_at FROM users WHERE id = 83") == [[@now]]
  end

  test "after a sweep only points created since five minutes before it count" do
    F.user!(84, %{"timezone" => "Etc/UTC"}, %{"stats_swept_at" => "2026-10-03T11:00:00"})
    F.point!(8401, 84, F.ts(2024, 1, 10), %{"created_at" => "2026-10-03T10:54:00"})
    F.point!(8402, 84, F.ts(2024, 2, 10), %{"created_at" => "2026-10-03T10:56:00"})
    F.point!(8403, 84, F.ts(2024, 3, 10), %{"created_at" => "2026-10-03T11:30:00"})

    assert BulkCalculator.call(ScratchRepo, 84, now: @now) == :ok
    assert months(84) == [[2024, 2, true], [2024, 3, true]]
  end

  test "stale statistics are repaired with jitter, without notifications, and deferred" do
    F.user!(85, %{"timezone" => "Etc/UTC"}, %{"stats_swept_at" => "2026-10-03T11:00:00"})
    F.stat!(8501, 85, 2023, 5, %{"calculation_version" => 2})
    F.stat!(8502, 85, 2023, 6, %{"calculation_version" => 3})
    F.stat!(8503, 85, 2023, 7, %{"calculation_version" => 1})
    F.point!(8504, 85, F.ts(2023, 7, 10), %{"created_at" => "2026-10-03T11:30:00"})

    assert BulkCalculator.call(ScratchRepo, 85, now: @now, clock: @t0, jitter: fn -> 1_234 end) ==
             :ok

    assert F.calculations() == [
             %{
               "user_id" => 85,
               "year" => 2023,
               "month" => 7,
               "notify_on_failure" => true,
               "run_at" => @t0
             },
             %{
               "user_id" => 85,
               "year" => 2023,
               "month" => 5,
               "notify_on_failure" => false,
               "run_at" => @t0 + 1_234
             }
           ]

    assert rows("SELECT month, repair_deferred_at FROM stats WHERE user_id = 85 ORDER BY month") ==
             [[5, @now], [6, nil], [7, nil]]
  end

  test "an account never swept starts from its newest statistics update" do
    F.user!(86, %{"timezone" => "Etc/UTC"})

    F.stat!(8601, 86, 2024, 1, %{
      "calculation_version" => 3,
      "updated_at" => "2026-10-01T00:00:00"
    })

    F.point!(8602, 86, F.ts(2026, 9, 30))
    F.point!(8603, 86, F.ts(2026, 10, 2))

    assert BulkCalculator.call(ScratchRepo, 86, now: @now) == :ok
    assert months(86) == [[2026, 10, true]]
  end

  test "a missing user raises, so the sweep counts it as failed" do
    assert_raise ArgumentError, fn -> BulkCalculator.call(ScratchRepo, 9_999, now: @now) end
  end

  defp months(user_id),
    do:
      for(
        %{"user_id" => ^user_id, "year" => year, "month" => month, "notify_on_failure" => notify} <-
          F.calculations(),
        do: [year, month, notify]
      )
end
