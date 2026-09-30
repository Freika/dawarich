defmodule Dawarich.Tracks.ChunkWorkerTest do
  use Dawarich.TracksCase, async: true, group: :scratch_db

  alias Dawarich.Tracks.{BoundaryWorker, ChunkWorker, RangeWorker, Settings}

  for name <- ~w(range_kept range_orphans range_two_trackers range_untracked_only range_q2) do
    @name name

    test "reproduces Rails chunk output: #{name}" do
      %{call: calls, expected: expected} = TracksFixtures.load!(ScratchRepo, @name)
      user = Settings.load!(ScratchRepo, 1)

      known =
        Enum.reduce(calls, identities(), fn call, known ->
          id = generate_chunks!(user, call)
          known = Map.merge(known, identities())

          :ok =
            BoundaryWorker.run(ScratchRepo, oban(), %{"generation_id" => id, "poll_count" => 0})

          Map.merge(known, identities())
        end)

      assert actual_tracks() == expected_tracks(expected)
      assert point_identities() == expected_point_identities(expected)
      assert actual_segments() == expected_segments(expected)
      assert Enum.sort(events(known)) == Enum.sort(expected_events(expected))
    end
  end

  test "the attached singleton is saved like point.update!" do
    %{call: [call]} = TracksFixtures.load!(ScratchRepo, "range_orphans")
    user = Settings.load!(ScratchRepo, 1)

    [singleton] =
      for p <- TracksFixtures.read!("range_orphans")["input"]["points"],
          p["tracker_id"] == "device-e" and p["track_id"] == nil,
          do: p["id"]

    before = Map.new(rows("SELECT id, updated_at FROM points"), &List.to_tuple/1)

    generate_chunks!(user, call)

    after_run = rows("SELECT id, lock_version, updated_at FROM points ORDER BY id")

    assert [[^singleton, 1, updated_at]] =
             Enum.filter(after_run, fn [_, version, _] -> version > 0 end)

    assert NaiveDateTime.compare(updated_at, before[singleton]) == :gt
    assert point_track_ids()[singleton] != nil
  end

  test "a lost race skips only its segment" do
    user = user!()
    t = 1_790_000_000
    lost = [point!(user.id, t, 12.3731, 51.3397), point!(user.id, t + 60, 12.3741, 51.3407)]

    kept = [
      point!(user.id, t + 120, 12.3751, 51.3417, tracker_id: "device-b"),
      point!(user.id, t + 180, 12.3761, 51.3427, tracker_id: "device-b")
    ]

    rows(
      "INSERT INTO tracks (user_id, tracker_id, start_at, end_at, original_path, created_at, updated_at) " <>
        "VALUES ($1, '', to_timestamp($2::bigint) AT TIME ZONE 'UTC', to_timestamp($3::bigint) AT TIME ZONE 'UTC', " <>
        "ST_GeomFromText('LINESTRING(12.3731 51.3397,12.3741 51.3407)', 4326), now(), now())",
      [user.id, t, t + 60]
    )

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        id =
          generate_chunks!(user, %{
            "start_at" => t - 3_600,
            "end_at" => t + 3_600,
            "zone" => "UTC",
            "mode" => "bulk",
            "untracked_only" => true,
            "import_id" => nil
          })

        assert rows("SELECT completed_chunks, tracks_created FROM phoenix.track_generations") ==
                 [[1, 1]]

        assert [["running" | _]] = generation(id)
      end)

    assert log =~ "race_winner_not_visible"
    assert Enum.map(lost, &point_track_ids()[&1]) == [nil, nil]
    assert kept |> Enum.map(&point_track_ids()[&1]) |> Enum.uniq() |> length() == 1
    refute point_track_ids()[hd(kept)] == nil
  end

  test "the final failed attempt fails the generation" do
    user = user!()
    t = 1_790_000_000
    point!(user.id, t, 12.3731, 51.3397)
    point!(user.id, t + 60, 12.3741, 51.3407)
    id = Ecto.UUID.generate()

    :ok =
      RangeWorker.run(ScratchRepo, oban(), %{
        "event_id" => id,
        "user_id" => user.id,
        "start_at" => iso(t - 3_600),
        "end_at" => iso(t + 3_600),
        "time_zone" => "UTC",
        "mode" => "bulk",
        "untracked_only" => true,
        "import_id" => nil,
        "low_priority" => false
      })

    [[args]] = chunk_jobs(id)
    raising = fn :loaded -> raise "boom" end

    for {attempt, status} <- [{2, "running"}, {3, "failed"}] do
      assert_raise RuntimeError, "boom", fn ->
        ChunkWorker.run(ScratchRepo, oban(), args,
          attempt: attempt,
          max_attempts: 3,
          hook: raising
        )
      end

      assert [[^status, 1, 0, 0, 0, _]] = generation(id)
    end

    assert [["failed", 1, 0, 0, 0, "boom"]] = generation(id)
    assert rows("SELECT count(*) FROM tracks") == [[0]]
  end
end
