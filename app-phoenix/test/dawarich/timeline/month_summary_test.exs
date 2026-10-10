defmodule Dawarich.Timeline.MonthSummaryTest do
  use Dawarich.DataCase, async: true
  alias Dawarich.Test.FrameSeeds, as: S
  alias Dawarich.Timeline.MonthSummary

  setup do
    %{user: S.user!(7031)}
  end

  @now ~U[2026-09-29 10:00:00Z]

  defp cell(summary, date), do: summary.weeks |> List.flatten() |> Enum.find(&(&1.date == date))

  test "a Monday-first 6×7 grid around the month", %{user: user} do
    summary = MonthSummary.build(user, "2026-09", nil, @now)

    assert summary.month == "2026-09"
    assert length(summary.weeks) == 6 and Enum.all?(summary.weeks, &(length(&1) == 7))
    assert hd(hd(summary.weeks)).date == "2026-08-31"
    refute hd(hd(summary.weeks)).in_month
  end

  test "visit minutes, track seconds split at local midnight, point-only days, suggestions", %{
    user: user
  } do
    S.visit!(user.id, 7131, %{
      started_at: ~N[2026-09-03 08:00:00],
      ended_at: ~N[2026-09-03 10:00:00],
      duration: 120
    })

    S.visit!(user.id, 7132, %{
      started_at: ~N[2026-09-10 08:00:00],
      ended_at: ~N[2026-09-10 09:00:00],
      duration: 60,
      status: 0
    })

    S.track!(user.id, 7231, %{
      start_at: ~N[2026-09-20 21:00:00],
      end_at: ~N[2026-09-20 23:00:00],
      duration: 7200
    })

    S.track!(user.id, 7232, %{
      start_at: ~N[2026-09-23 21:59:59],
      end_at: ~N[2026-09-23 22:00:01],
      duration: 3
    })

    S.visit!(user.id, 7137, %{
      started_at: ~N[2026-09-30 22:00:00],
      ended_at: ~N[2026-09-30 22:30:00],
      duration: 30
    })

    S.point!(user.id, 7631, DateTime.to_unix(~U[2026-09-25 10:00:00Z]))

    summary = MonthSummary.build(user, "2026-09", nil, @now)
    october = MonthSummary.build(user, "2026-10", nil, @now)

    assert cell(summary, "2026-09-03").tracked_seconds == 7200

    assert {cell(summary, "2026-09-23").tracked_seconds,
            cell(summary, "2026-09-24").tracked_seconds} == {1, 1}

    assert cell(summary, "2026-10-01").visit_count == 0
    assert cell(october, "2026-10-01").tracked_seconds == 1800
    assert cell(summary, "2026-09-10").suggested_count == 1

    assert {cell(summary, "2026-09-20").tracked_seconds,
            cell(summary, "2026-09-21").tracked_seconds} == {3600, 3600}

    assert cell(summary, "2026-09-20").track_count == 1 and
             cell(summary, "2026-09-21").track_count == 0

    assert cell(summary, "2026-09-25").heat_bucket == 1
    assert cell(summary, "2026-09-03").heat_bucket == 5
    assert cell(summary, "2026-09-26").heat_bucket == 0
  end

  test "heat is graded against the busiest day of this month only", %{user: user} do
    S.track!(user.id, 7235, %{
      start_at: ~N[2026-08-31 10:00:00],
      end_at: ~N[2026-08-31 23:00:00],
      duration: 46_800
    })

    S.visit!(user.id, 7133, %{
      started_at: ~N[2026-09-02 08:00:00],
      ended_at: ~N[2026-09-02 09:00:00],
      duration: 60
    })

    S.visit!(user.id, 7134, %{
      started_at: ~N[2026-09-04 08:00:00],
      ended_at: ~N[2026-09-04 08:21:00],
      duration: 21
    })

    S.visit!(user.id, 7135, %{
      started_at: ~N[2026-10-01 08:00:00],
      ended_at: ~N[2026-10-01 18:00:00],
      duration: 600
    })

    summary = MonthSummary.build(user, "2026-09", nil, @now)

    assert cell(summary, "2026-08-31").tracked_seconds == 43_200

    assert {cell(summary, "2026-09-01").tracked_seconds, cell(summary, "2026-09-02").heat_bucket} ==
             {3600, 5}

    assert cell(summary, "2026-09-04").heat_bucket == 2
    assert cell(summary, "2026-08-31").heat_bucket == 5
    assert cell(summary, "2026-10-01").heat_bucket == 0
  end

  test "a restricted user's cells before the data window are disabled and their rows ignored", %{
    user: user
  } do
    S.visit!(user.id, 7136, %{
      started_at: ~N[2025-09-28 08:00:00],
      ended_at: ~N[2025-09-28 09:00:00],
      duration: 60
    })

    summary = MonthSummary.build(user, "2025-09", @now, @now)

    assert cell(summary, "2025-09-28").disabled
    assert cell(summary, "2025-09-28").tracked_seconds == 0
    refute cell(summary, "2025-09-29").disabled
  end

  test "a blank month is the current month in the user's zone", %{user: user} do
    assert MonthSummary.build(user, "", nil, ~U[2026-09-30 22:30:00Z]).month == "2026-10"
    assert MonthSummary.build(user, nil, nil, @now).month == "2026-09"
  end
end
