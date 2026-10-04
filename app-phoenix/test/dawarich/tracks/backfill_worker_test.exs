defmodule Dawarich.Tracks.BackfillWorkerTest do
  use Dawarich.JobsCase, async: true, group: :scratch_db

  alias Dawarich.Jobs.{Ownership, Processed}
  alias Dawarich.Tracks.{BackfillRanges, BackfillWorker, RangeWorker}

  @now ~U[2026-04-02 12:00:00.123456Z]

  setup do
    start_oban(__MODULE__)
    :ok
  end

  test "consumes one cycle into the source ambient-day window and realtime cap" do
    rows(
      "INSERT INTO users (id, email, settings, created_at, updated_at) VALUES (1, 'k8@example.test', $1, now(), now())",
      [%{"timezone" => "Asia/Tokyo"}]
    )

    Ownership.put!(ScratchRepo, "command:tracks.generate_range", :oban)

    for {zone, earliest, latest, from, until} <- [
          {"Europe/Berlin", ~U[2026-03-29 12:00:00Z], ~U[2026-03-29 14:00:00Z],
           "2026-03-28T23:00:00.000000Z", "2026-03-29T21:59:59.999999Z"},
          {"Asia/Tokyo", ~U[2026-03-29 12:00:00Z], ~U[2026-03-29 14:00:00Z],
           "2026-03-28T15:00:00.000000Z", "2026-03-29T14:59:59.999999Z"},
          {"Etc/UTC", ~U[2026-04-01 12:00:00Z], @now, "2026-04-01T00:00:00.000000Z",
           "2026-04-02T06:00:00.123456Z"}
        ] do
      args = put(1, earliest, latest, zone)
      assert {:ok, decoded} = BackfillWorker.args_from_command(1, Map.delete(args, "event_id"))
      assert decoded == Map.delete(args, "event_id")
      assert BackfillWorker.args_from_command(2, decoded) == {:error, "unsupported_version"}

      assert BackfillWorker.args_from_command(1, Map.put(decoded, "extra", true)) ==
               {:error, "invalid_payload"}

      assert BackfillWorker.args_from_command(1, %{decoded | "cycle_id" => "bad"}) ==
               {:error, "invalid_payload"}

      assert BackfillWorker.run(ScratchRepo, __MODULE__, args, now: @now) == :ok

      assert [[payload]] =
               rows("SELECT args FROM oban.oban_jobs WHERE args->>'event_id' = $1", [
                 args["cycle_id"]
               ])

      assert payload == %{
               "event_id" => args["cycle_id"],
               "user_id" => 1,
               "start_at" => from,
               "end_at" => until,
               "time_zone" => zone,
               "mode" => "bulk",
               "untracked_only" => true,
               "import_id" => nil,
               "low_priority" => false
             }

      assert [[inspect(RangeWorker)]] ==
               rows("SELECT worker FROM oban.oban_jobs WHERE args->>'event_id' = $1", [
                 args["cycle_id"]
               ])

      assert Processed.done?(ScratchRepo, args["cycle_id"])
      assert rows("SELECT count(*) FROM phoenix.track_backfill_ranges") == [[0]]
    end
  end

  test "failed publication retains range and a replay cannot consume a newer cycle" do
    for owner <- [:oban, :sidekiq] do
      Ownership.put!(ScratchRepo, "command:tracks.generate_range", owner)
      args = put(1, ~U[2026-03-29 12:00:00Z], @now, "Europe/Berlin")
      sentinel = put(2, ~U[2026-03-29 12:00:00Z], @now, "Asia/Tokyo")
      snapshot = rows("SELECT * FROM phoenix.track_backfill_ranges ORDER BY user_id")
      fail = fn :publishing -> raise "child insertion failed" end

      assert BackfillWorker.run(ScratchRepo, __MODULE__, args, now: @now, hook: fail) ==
               {:snooze, 60}

      assert rows("SELECT * FROM phoenix.track_backfill_ranges ORDER BY user_id") == snapshot
      refute Processed.done?(ScratchRepo, args["cycle_id"])
      assert rows("SELECT count(*) FROM oban.oban_jobs") == [[0]]
      assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
      assert BackfillWorker.run(ScratchRepo, __MODULE__, args, now: @now) == :ok
      assert BackfillWorker.run(ScratchRepo, __MODULE__, args, now: @now) == :ok

      if owner == :oban do
        assert rows("SELECT count(*) FROM oban.oban_jobs") == [[1]]
      else
        assert [["tracks_generate_range", payload]] =
                 rows("SELECT kind, payload FROM phoenix.rails_commands")

        assert map_size(payload) == 8
        assert payload["untracked_only"] == true
      end

      fresh = put(1, ~U[2026-03-30 12:00:00Z], @now, "Etc/UTC")
      assert BackfillWorker.run(ScratchRepo, __MODULE__, args, now: @now) == :ok

      assert rows("SELECT cycle_id::text FROM phoenix.track_backfill_ranges ORDER BY user_id") ==
               [[fresh["cycle_id"]], [sentinel["cycle_id"]]]

      rows("TRUNCATE phoenix.track_backfill_ranges, phoenix.rails_commands, oban.oban_jobs")
    end
  end

  defp put(id, from, until, zone) do
    {:ok, {:inserted, range}} =
      BackfillRanges.put(
        ScratchRepo,
        id,
        [DateTime.to_unix(from), DateTime.to_unix(until)],
        zone,
        @now,
        fn _ -> :ok end
      )

    %{
      "user_id" => id,
      "cycle_id" => range.cycle_id,
      "time_zone" => zone,
      "event_id" => range.cycle_id
    }
  end
end
