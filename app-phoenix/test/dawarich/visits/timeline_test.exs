defmodule Dawarich.Visits.TimelineTest do
  use Dawarich.DataCase, async: true
  alias Dawarich.Accounts.Scope
  alias Dawarich.Visits.Timeline
  alias Dawarich.Test.FrameSeeds, as: S
  @now ~U[2026-10-01 10:00:00Z]
  @params %{"start_at" => "2026-09-27T00:00:00", "end_at" => "2026-09-27T23:59:59"}
  setup do
    user = S.user!(8111)
    %{scope: Scope.for_user(user, "de")}
  end

  test "timeline cursor windows never lose or duplicate tied rows", %{scope: scope} do
    for i <- 1..205,
        do:
          S.visit!(scope.user.id, 81000 + i, %{
            started_at: ~N[2026-09-27 07:00:00],
            ended_at: ~N[2026-09-27 08:00:00]
          })

    assert {:ok, a} = Timeline.load(scope, @params, now: @now, self_hosted: true)
    assert length(a.rows) == 100
    assert a.stream_limit == 200
    assert a.reset == true

    assert {:ok, b} =
             Timeline.load(scope, Map.put(@params, "cursor", a.next_cursor),
               now: @now,
               self_hosted: true
             )

    assert length(b.rows) == 100
    assert b.reset == false

    assert {:ok, c} =
             Timeline.load(scope, Map.put(@params, "cursor", b.next_cursor),
               now: @now,
               self_hosted: true
             )

    ids = Enum.map(a.rows ++ b.rows ++ c.rows, & &1.visit_id)
    assert ids == Enum.to_list(81205..81001//-1)
    assert c.next_cursor == nil

    assert {:error, :invalid_input} =
             Timeline.load(scope, Map.put(@params, "cursor", "bad"), now: @now, self_hosted: true)
  end

  test "timeline final-second visit precedes a continuation across cursor boundaries", %{
    scope: scope
  } do
    for i <- 1..99 do
      S.visit!(scope.user.id, 86000 + i, %{
        started_at: ~N[2026-09-27 07:00:00],
        ended_at: ~N[2026-09-27 08:00:00]
      })
    end

    S.visit!(scope.user.id, 86200, %{
      started_at: ~N[2026-09-27 21:59:59],
      ended_at: ~N[2026-09-27 22:00:00]
    })

    S.track!(scope.user.id, 86300, %{
      start_at: ~N[2026-09-26 20:00:00],
      end_at: ~N[2026-09-28 03:00:00],
      duration: 111_600
    })

    assert {:ok, first} = Timeline.load(scope, @params, now: @now, self_hosted: true)
    [source] = Dawarich.Timeline.Days.load(scope.user, first.window, nil).days
    assert length(source.entries) == 101
    assert List.last(first.rows).visit_id == 86200

    assert {:ok, second} =
             Timeline.load(scope, Map.put(@params, "cursor", first.next_cursor),
               now: @now,
               self_hosted: true
             )

    assert [%{track_id: 86300, continuation_of_date: "2026-09-26"}] = second.rows
    key = fn entry -> {entry.type, entry[:visit_id], entry[:track_id]} end
    assert Enum.map(first.rows ++ second.rows, key) == Enum.map(source.entries, key)
    assert second.next_cursor == nil
  end

  test "calendar totals include rows beyond the visible timeline window", %{scope: scope} do
    for i <- 1..105,
        do:
          S.visit!(scope.user.id, 82000 + i, %{
            started_at: ~N[2026-09-27 07:00:00],
            ended_at: ~N[2026-09-27 08:00:00],
            duration: 60
          })

    assert {:ok, page} = Timeline.load(scope, @params, now: @now, self_hosted: true)
    cell = page.calendar.weeks |> List.flatten() |> Enum.find(&(&1.date == "2026-09-27"))
    assert length(page.rows) == 100
    assert cell.visit_count == 105
    assert cell.tracked_seconds == 105 * 3600
    assert hd(page.days).summary.confirmed_count == 105
  end

  test "timeline preserves DST continuation and Lite admission", %{scope: scope} do
    S.track!(scope.user.id, 83001, %{
      start_at: ~N[2026-03-28 22:00:00],
      end_at: ~N[2026-03-29 22:00:00],
      duration: 86400
    })

    params = %{"start_at" => "2026-03-29T00:00:00", "end_at" => "2026-03-29T23:59:59"}
    assert {:ok, page} = Timeline.load(scope, params, now: @now, self_hosted: true)
    assert [%{type: "journey", continuation_of_date: "2026-03-28"}] = page.rows
    assert hd(page.rows).day_distance > 0
    Dawarich.Repo.query!("UPDATE users SET plan=0 WHERE id=$1", [scope.user.id], log: false)

    assert {:ok, locked} =
             Timeline.load(scope, params, now: ~U[2028-03-30 12:00:00Z], self_hosted: false)

    assert locked.rows == []
    assert locked.restricted == true

    assert {:error, :limit} =
             Timeline.load(scope, %{"start_at" => "2026-01-01", "end_at" => "2026-04-01"},
               now: @now,
               self_hosted: true
             )
  end

  test "timeline calendar rejects malformed input and changed session identity", %{scope: scope} do
    assert {:ok, calendar} = Timeline.calendar(scope, "2026-09", now: @now, self_hosted: true)
    assert calendar.month == "2026-09"
    assert length(List.flatten(calendar.weeks)) == 42

    for month <- [[], %{}, "bad", String.duplicate("9", 1000)] do
      assert {:error, :invalid_input} =
               Timeline.calendar(scope, month, now: @now, self_hosted: true)
    end

    Dawarich.Repo.query!(
      "UPDATE users SET encrypted_password='changed-session-00000000000000000' WHERE id=$1",
      [scope.user.id],
      log: false
    )

    assert {:error, :stale_session} =
             Timeline.calendar(scope, "2026-09", now: @now, self_hosted: true)

    assert {:error, :stale_session} = Timeline.load(scope, @params, now: @now, self_hosted: true)
  end

  test "timeline share expansion stays inside the admitted window" do
    shares = Dawarich.Timeline.Sql.shares("t", "$1::date", "$2::date")

    sql =
      "WITH z AS (SELECT 'Europe/Berlin'::text AS name) SELECT s.day,s.seconds FROM (VALUES ('2020-01-01'::timestamp,'2028-01-01'::timestamp)) t(start_at,end_at) CROSS JOIN z " <>
        shares <> " ORDER BY s.day"

    result = Dawarich.Repo.query!(sql, [~D[2026-03-28], ~D[2026-03-30]], log: false).rows
    assert Enum.map(result, &hd/1) == [~D[2026-03-28], ~D[2026-03-29], ~D[2026-03-30]]
    assert Enum.at(result, 1) == [~D[2026-03-29], 82800.0]
  end

  test "timeline full range summary and bounds retain source values", %{scope: scope} do
    S.place!(scope.user.id, 84001, "Place")

    S.visit!(scope.user.id, 84002, %{
      started_at: ~N[2026-09-27 07:00:00],
      ended_at: ~N[2026-09-27 08:00:00],
      place_id: 84001,
      duration: 60
    })

    S.track!(scope.user.id, 84003, %{
      start_at: ~N[2026-09-27 08:00:00],
      end_at: ~N[2026-09-27 09:00:00],
      distance: 3000,
      duration: 3600
    })

    S.segment!(84003, 84004, %{
      transportation_mode: 2,
      distance: 3000,
      duration: 3600,
      confidence_score: 0.9
    })

    assert {:ok, page} = Timeline.load(scope, @params, now: @now, self_hosted: true)
    [source] = Dawarich.Timeline.Days.load(scope.user, page.window, nil).days
    assert hd(page.days).summary == source.summary
    assert hd(page.days).bounds == source.bounds
  end
end
