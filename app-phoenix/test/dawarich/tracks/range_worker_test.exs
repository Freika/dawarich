defmodule Dawarich.Tracks.RangeWorkerTest do
  use Dawarich.TracksCase

  alias Dawarich.Tracks.{PerUserLock, RangeWorker}

  @t 1_790_000_000

  defp user_with_points! do
    user = user!()
    point!(user.id, @t, 12.3731, 51.3397)
    point!(user.id, @t + 60, 12.3741, 51.3407)
    user
  end

  defp args(user, overrides \\ %{}) do
    Map.merge(
      %{
        "event_id" => Ecto.UUID.generate(),
        "user_id" => user.id,
        "start_at" => iso(@t - 3_600),
        "end_at" => iso(@t + 3_600),
        "time_zone" => "Europe/Berlin",
        "mode" => "bulk",
        "untracked_only" => false,
        "import_id" => nil,
        "low_priority" => false
      },
      overrides
    )
  end

  defp track_ids, do: rows("SELECT id FROM tracks ORDER BY id") |> List.flatten()

  test "a replay after start! never cleans again" do
    user = user_with_points!()
    track!(user.id, "old", @t - 600, @t - 300)
    args = args(user)

    assert RangeWorker.run(ScratchRepo, oban(), args) == :ok
    assert track_ids() == []
    assert generation(args["event_id"]) == [["running", 1, 0, 0, 0, nil]]

    fresh = track!(user.id, "fresh", @t - 600, @t - 300)

    assert RangeWorker.run(ScratchRepo, oban(), args) == :ok
    assert track_ids() == [fresh]
    assert rows("SELECT count(*) FROM phoenix.track_generations") == [[1]]
    assert length(chunk_jobs(args["event_id"])) == 1
  end

  test "a held lock is lock_busy and cleans nothing" do
    user = user_with_points!()
    track = track!(user.id, "old", @t - 600, @t - 300)
    rails = rails_redis!()
    Redix.command!(rails, ["SET", PerUserLock.key(user.id), "rails-token", "PX", "60000"])
    args = args(user)

    assert RangeWorker.run(ScratchRepo, oban(), args, lock: [timeout_ms: 200]) ==
             {:error, :lock_busy}

    assert track_ids() == [track]
    assert rows("SELECT count(*) FROM phoenix.track_generations") == [[0]]
    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[0]]
    assert tracks_changed() == []
    assert Redix.command!(rails, ["GET", PerUserLock.key(user.id)]) == "rails-token"
  end

  test "low-priority generations schedule priority-3 jobs" do
    user = user_with_points!()

    for low_priority <- [true, false],
        do:
          :ok =
            RangeWorker.run(ScratchRepo, oban(), args(user, %{"low_priority" => low_priority}))

    assert rows(
             "SELECT worker, (args->>'poll_count') IS NULL, priority FROM oban.oban_jobs ORDER BY id"
           ) == [
             ["Dawarich.Tracks.ChunkWorker", true, 3],
             ["Dawarich.Tracks.BoundaryWorker", false, 3],
             ["Dawarich.Tracks.ChunkWorker", true, 0],
             ["Dawarich.Tracks.BoundaryWorker", false, 0]
           ]
  end

  test "decodes version 1 payloads exactly" do
    payload = %{
      "user_id" => 7,
      "start_at" => "2026-03-28T00:00:00.000000+01:00",
      "end_at" => nil,
      "time_zone" => "Europe/Berlin",
      "mode" => "daily",
      "untracked_only" => false,
      "import_id" => nil,
      "low_priority" => true
    }

    assert RangeWorker.args_from_command(1, payload) == {:ok, payload}

    assert RangeWorker.args_from_command(1, %{payload | "import_id" => 3}) ==
             {:ok, %{payload | "import_id" => 3}}

    for bad <- [
          Map.put(payload, "extra", 1),
          Map.delete(payload, "low_priority"),
          %{payload | "user_id" => "7"},
          %{payload | "start_at" => "yesterday"},
          %{payload | "mode" => "weekly"},
          %{payload | "untracked_only" => nil},
          %{payload | "import_id" => "3"},
          %{payload | "time_zone" => nil}
        ],
        do: assert(RangeWorker.args_from_command(1, bad) == {:error, "invalid_payload"})

    assert RangeWorker.args_from_command(2, payload) == {:error, "unsupported_version"}
  end
end
