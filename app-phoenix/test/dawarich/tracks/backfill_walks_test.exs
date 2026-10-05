defmodule Dawarich.Tracks.BackfillWalksTest do
  use Dawarich.JobsCase, async: true, group: :scratch_db

  import Dawarich.LockRace
  alias Dawarich.Jobs.Ownership
  alias Dawarich.Tracks.BackfillWalks

  @now ~U[2026-10-04 12:00:00.000000Z]

  test "one user walk refreshes twelve hours and completion blocks seven days" do
    assert {:ok, {:inserted, walk}} = schedule(1, @now)
    assert walk.cursor_timestamp == nil
    assert walk.expires_at == DateTime.add(@now, 43_200)
    assert walk.time_zone == "Europe/Berlin"
    assert {:ok, :occupied} = schedule(1, DateTime.add(@now, 60))
    assert rows("SELECT count(*) FROM public.job_outbox") == [[1]]

    now = DateTime.add(@now, 120)
    select = fn -> {100, 2_592_100} end

    assert {:ok, {:selected, step}} =
             BackfillWalks.select(ScratchRepo, 1, walk.walk_id, nil, select)

    assert step.selected_start_timestamp == 100
    assert step.selected_end_timestamp == 2_592_100

    assert {:ok, {:selected, replay}} =
             BackfillWalks.select(ScratchRepo, 1, walk.walk_id, nil, fn ->
               flunk("selection repeated")
             end)

    assert replay == step

    assert {:error, :publication_failed} =
             BackfillWalks.advance(ScratchRepo, step, now, fn _ ->
               {:error, :publication_failed}
             end)

    assert rows("SELECT cursor_timestamp, step_event_id::text FROM phoenix.track_backfill_walks") ==
             [[nil, step.step_event_id]]

    assert {:ok, {:advanced, next}} = BackfillWalks.advance(ScratchRepo, step, now, &publish/1)
    assert next.cursor_timestamp == 100
    assert next.expires_at == DateTime.add(now, 43_200)
    assert next.step_event_id == nil
    assert next.selected_start_timestamp == nil
    assert next.selected_end_timestamp == nil
    assert {:ok, :stale} = BackfillWalks.advance(ScratchRepo, step, now, &publish/1)
    assert rows("SELECT count(*) FROM public.job_outbox") == [[2]]

    assert rows("SELECT scheduled_at FROM public.job_outbox ORDER BY scheduled_at DESC LIMIT 1") ==
             [[DateTime.add(now, 60)]]

    assert {:ok, :backoff} = BackfillWalks.finish(ScratchRepo, 1, walk.walk_id, 100, now)
    until = DateTime.add(now, 604_800)

    assert rows("SELECT state, expires_at FROM phoenix.track_backfill_walks") == [
             ["backoff", until]
           ]

    assert {:ok, :occupied} = schedule(1, DateTime.add(until, -1))
    assert {:ok, {:inserted, fresh}} = schedule(1, until)
    refute fresh.walk_id == walk.walk_id
    assert fresh.cursor_timestamp == nil
    assert {:ok, :stale} = BackfillWalks.finish(ScratchRepo, 1, walk.walk_id, 100, until)

    assert {:error, :publication_failed} =
             BackfillWalks.schedule(ScratchRepo, 2, "Etc/UTC", @now, fn _ ->
               {:error, :publication_failed}
             end)

    assert rows("SELECT count(*) FROM phoenix.track_backfill_walks WHERE user_id = 2") == [[0]]
  end

  test "simultaneous schedulers publish one walk and cannot clear another user" do
    Ownership.put!(ScratchRepo, "command:tracks.throttled_backfill", :oban)
    assert {:ok, {:inserted, other}} = schedule(2, @now)
    parent = self()

    holder =
      hold(fn ->
        assert {:ok, {:inserted, first}} = schedule(1, @now)
        send(parent, {:walk, first})
      end)

    assert_receive {:walk, first}
    second = Task.async(fn -> schedule(1, @now) end)
    assert settle(second, "INSERT INTO phoenix.track_backfill_walks%") == :blocked
    commit(holder)
    assert {:ok, :occupied} = Task.await(second)
    assert rows("SELECT aggregate_id FROM public.job_outbox ORDER BY aggregate_id") == [[1], [2]]
    assert {:ok, :stale} = BackfillWalks.release(ScratchRepo, 1, Ecto.UUID.generate())

    rows("UPDATE phoenix.track_backfill_walks SET walk_id = $1 WHERE user_id = 2", [
      Ecto.UUID.dump!(first.walk_id)
    ])

    assert {:ok, :released} = BackfillWalks.release(ScratchRepo, 1, first.walk_id)

    assert rows("SELECT user_id, time_zone, expires_at FROM phoenix.track_backfill_walks") == [
             [2, other.time_zone, other.expires_at]
           ]

    assert {:ok, :stale} = BackfillWalks.release(ScratchRepo, 1, first.walk_id)
  end

  defp schedule(id, now),
    do: BackfillWalks.schedule(ScratchRepo, id, "Europe/Berlin", now, &publish/1)

  defp publish(walk) do
    event = walk[:event_id] || walk.walk_id

    outbox!(
      event_id: event,
      command_type: "tracks.throttled_backfill",
      aggregate_id: walk.user_id,
      scheduled_at: walk.due_at,
      payload: %{
        "user_id" => walk.user_id,
        "walk_id" => walk.walk_id,
        "cursor_timestamp" => walk.cursor_timestamp,
        "time_zone" => walk.time_zone
      }
    )

    :ok
  end
end
