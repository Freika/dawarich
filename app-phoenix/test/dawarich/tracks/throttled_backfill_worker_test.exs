defmodule Dawarich.Tracks.ThrottledBackfillWorkerTest do
  use Dawarich.TracksCase, async: true, group: :tracks_db

  alias Dawarich.Jobs.{Ownership, Processed}
  alias Dawarich.Tracks.{BackfillWalks, ThrottledBackfillWorker}

  @now ~U[2026-10-04 12:00:00.000000Z]
  @epoch DateTime.to_unix(@now)
  @slice 2_592_000

  setup do
    Ownership.put!(ScratchRepo, "command:tracks.throttled_backfill", :oban)
    Ownership.put!(ScratchRepo, "command:tracks.generate_range", :oban)
    :ok
  end

  @tag a12f3b_case: "E14A2a"
  test "jumps gaps and starts one fixed thirty-day untracked low-priority slice" do
    user = user!(%{"timezone" => "Asia/Tokyo"})
    other = user!()
    cursor = @epoch - 100 * 86_400
    maximum = @epoch - 400 * 86_400
    point!(user.id, cursor, 1, 1)
    anomaly = point!(user.id, maximum, 1, 1)
    point!(user.id, maximum - 60, 1, 1)
    rows("UPDATE points SET anomaly = true WHERE id = $1", [anomaly])
    point!(other.id, cursor - 1, 1, 1)
    args = walk(user.id, cursor)

    rows("UPDATE phoenix.track_backfill_walks SET time_zone = 'Berlin' WHERE user_id = $1", [
      user.id
    ])

    payload = Map.delete(args, "event_id")
    assert ThrottledBackfillWorker.args_from_command(1, payload) == {:ok, payload}

    assert ThrottledBackfillWorker.args_from_command(2, payload) ==
             {:error, "unsupported_version"}

    assert ThrottledBackfillWorker.backoff(%Oban.Job{attempt: 1}) in 15..24
    assert ThrottledBackfillWorker.backoff(%Oban.Job{attempt: 2}) in 16..35

    assert ThrottledBackfillWorker.backoff(%Oban.Job{attempt: 10, max_attempts: 26}) in 6_576..6_675

    for invalid <- [
          Map.put(payload, "extra", 1),
          %{payload | "walk_id" => "bad"},
          %{payload | "cursor_timestamp" => "1"},
          %{payload | "user_id" => "1"}
        ] do
      assert ThrottledBackfillWorker.args_from_command(1, invalid) == {:error, "invalid_payload"}
    end

    parent = self()
    hook = fn {:starting, payload} -> send(parent, {:window, payload}) end
    assert ThrottledBackfillWorker.run(ScratchRepo, oban(), args, now: @now, hook: hook) == :ok
    assert_receive {:window, window}

    assert window == %{
             "user_id" => user.id,
             "event_id" => window["event_id"],
             "start_at" => iso(maximum - @slice),
             "end_at" => iso(maximum),
             "time_zone" => "Europe/Berlin",
             "mode" => "bulk",
             "untracked_only" => true,
             "low_priority" => true,
             "import_id" => nil
           }

    assert generation(window["event_id"]) == [["running", 1, 0, 0, 0, nil]]

    assert rows("SELECT low_priority, untracked_only, import_id FROM phoenix.track_generations") ==
             [[true, true, nil]]

    assert rows("SELECT priority FROM oban.oban_jobs WHERE worker <> $1", [
             inspect(ThrottledBackfillWorker)
           ]) == [[3], [3]]

    assert [[next, due]] = successors()
    assert next["cursor_timestamp"] == maximum - @slice
    assert next["walk_id"] == args["walk_id"]
    assert DateTime.from_naive!(due, "Etc/UTC") == DateTime.add(@now, 60)
    assert Processed.done?(ScratchRepo, window["event_id"])
  end

  @tag a12f3b_case: "E14A2b"
  test "failed start preserves cursor and successful replay has one delayed successor" do
    user = user!()
    point!(user.id, @epoch - 100, 1, 1)

    for owner <- [:oban, :sidekiq] do
      Ownership.put!(ScratchRepo, "command:tracks.generate_range", owner)
      Ownership.put!(ScratchRepo, "command:tracks.throttled_backfill", owner)
      args = walk(user.id, @epoch)
      fail = fn {:starting, _} -> raise "generation failed" end

      assert_raise RuntimeError, "generation failed", fn ->
        ThrottledBackfillWorker.run(ScratchRepo, oban(), args, now: @now, hook: fail)
      end

      assert [[@epoch, step, start_at, end_at]] = selection(user.id)
      assert start_at == @epoch - 100 - @slice
      assert end_at == @epoch - 100
      refute Processed.done?(ScratchRepo, step)
      assert rows("SELECT count(*) FROM phoenix.track_generations") == [[0]]
      assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
      assert successors() == []
      assert ThrottledBackfillWorker.run(ScratchRepo, oban(), args, now: @now) == :ok
      assert ThrottledBackfillWorker.run(ScratchRepo, oban(), args, now: @now) == :ok
      assert selection(user.id) == [[start_at, nil, nil, nil]]
      assert Processed.done?(ScratchRepo, step)

      if owner == :oban do
        assert length(successors()) == 1
        assert generation(step) == [["running", 1, 0, 0, 0, nil]]
      else
        assert [[range], [next]] = rows("SELECT payload FROM phoenix.rails_commands ORDER BY id")
        assert range["start_at"] == iso(start_at)
        assert range["end_at"] == iso(end_at)
        assert next["walk_id"] == args["walk_id"]
        assert next["cursor_timestamp"] == start_at
        assert next["scheduled_at"] == DateTime.to_iso8601(DateTime.add(@now, 60))
      end

      rows(
        "TRUNCATE phoenix.track_backfill_walks, phoenix.track_generations, phoenix.track_generation_chunks, phoenix.rails_commands, oban.oban_jobs"
      )
    end
  end

  test "empty history starts backoff and missing user releases only its walk" do
    user = user!()
    other = user!()
    args = walk(user.id, nil)
    sentinel = walk(other.id, nil)
    assert ThrottledBackfillWorker.run(ScratchRepo, oban(), args, now: @now) == :ok

    assert rows("SELECT state, expires_at FROM phoenix.track_backfill_walks WHERE user_id = $1", [
             user.id
           ]) == [["backoff", DateTime.add(@now, 604_800)]]

    assert successors() == []
    assert rows("SELECT count(*) FROM phoenix.track_generations") == [[0]]
    missing = walk(0, nil)
    assert ThrottledBackfillWorker.run(ScratchRepo, oban(), missing, now: @now) == :ok
    rows("UPDATE users SET deleted_at = now() WHERE id = $1", [other.id])
    assert ThrottledBackfillWorker.run(ScratchRepo, oban(), sentinel, now: @now) == :ok
    assert rows("SELECT user_id FROM phoenix.track_backfill_walks") == [[user.id]]
  end

  test "retry reuses selected bounds after a newer eligible point arrives" do
    user = user!()
    point!(user.id, @epoch - 1_000, 1, 1)
    args = walk(user.id, @epoch)
    fail = fn {:starting, _} -> raise "parent start failed" end

    assert_raise RuntimeError, "parent start failed", fn ->
      ThrottledBackfillWorker.run(ScratchRepo, oban(), args, now: @now, hook: fail)
    end

    assert [[@epoch, step, first, last]] = selection(user.id)
    assert last == @epoch - 1_000
    point!(user.id, @epoch - 100, 1, 1)
    parent = self()
    hook = fn {:starting, payload} -> send(parent, {:retry, payload}) end
    assert ThrottledBackfillWorker.run(ScratchRepo, oban(), args, now: @now, hook: hook) == :ok
    assert_receive {:retry, payload}
    assert payload["event_id"] == step
    assert payload["start_at"] == iso(first)
    assert payload["end_at"] == iso(last)
    assert selection(user.id) == [[first, nil, nil, nil]]
    assert [[next, _]] = successors()
    assert next["cursor_timestamp"] == first
    assert ThrottledBackfillWorker.run(ScratchRepo, oban(), args, now: @now) == :ok
    assert length(successors()) == 1
    assert generation(step) == [["running", 1, 0, 0, 0, nil]]
  end

  defp walk(id, cursor) do
    {:ok, {:inserted, walk}} =
      BackfillWalks.schedule(ScratchRepo, id, "Europe/Berlin", @now, fn _ -> :ok end)

    rows(
      "UPDATE phoenix.track_backfill_walks SET cursor_timestamp = $2::bigint WHERE user_id = $1",
      [id, cursor]
    )

    %{
      "user_id" => id,
      "walk_id" => walk.walk_id,
      "cursor_timestamp" => cursor,
      "time_zone" => walk.time_zone,
      "event_id" => walk.walk_id
    }
  end

  defp selection(id),
    do:
      rows(
        "SELECT cursor_timestamp, step_event_id::text, selected_start_timestamp, selected_end_timestamp FROM phoenix.track_backfill_walks WHERE user_id = $1",
        [id]
      )

  defp successors,
    do:
      rows("SELECT args, scheduled_at FROM oban.oban_jobs WHERE worker = $1 ORDER BY id", [
        inspect(ThrottledBackfillWorker)
      ])
end
