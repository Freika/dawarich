defmodule Dawarich.Tracks.BuilderTest do
  use Dawarich.TracksCase

  import ExUnit.CaptureLog

  alias Dawarich.Tracks.{Builder, Points, Settings}

  @start 1_790_834_400
  @finish 1_790_835_300

  setup do
    %{call: [call], expected: expected} = TracksFixtures.load!(ScratchRepo, "elevation")
    user = Settings.load!(ScratchRepo, 1)

    points =
      Points.load_chunk(ScratchRepo, 1, @start, @finish, untracked_only: false, import_id: nil)

    %{call: call, expected: expected, user: user, points: points}
  end

  defp winner!(tracker_id) do
    [[id]] =
      rows(
        "INSERT INTO tracks (user_id, tracker_id, start_at, end_at, original_path, distance, duration, avg_speed, " <>
          "created_at, updated_at) VALUES (1, $1, to_timestamp($2) AT TIME ZONE 'UTC', " <>
          "to_timestamp($3) AT TIME ZONE 'UTC', ST_GeomFromText('LINESTRING(12.3 51.3,12.4 51.4)', 4326), " <>
          "1, 1, 1.0, now(), now()) RETURNING id",
        [tracker_id, @start, @finish]
      )

    id
  end

  test "values match Rails", %{call: call, expected: expected, user: user, points: points} do
    assert {:ok, track} =
             Builder.create_track!(ScratchRepo, user, points, call["pre_calculated_distance"],
               tracker_id: call["tracker_id"],
               skip_segment_detection: call["skip_segment_detection"]
             )

    want = expected["elevation_track"]

    assert rows(
             "SELECT tracker_id, floor(extract(epoch FROM start_at))::bigint, floor(extract(epoch FROM end_at))::bigint, " <>
               "ST_AsText(original_path), distance, duration, avg_speed, elevation_gain, elevation_loss, " <>
               "elevation_max, elevation_min, dominant_mode, import_id FROM tracks WHERE id = $1",
             [track.id]
           ) == [
             Enum.map(
               ~w(tracker_id start_at end_at original_path_wkt distance duration avg_speed elevation_gain
                  elevation_loss elevation_max elevation_min dominant_mode import_id),
               &want[&1]
             )
           ]

    assert Enum.map(points, &point_track_ids()[&1.id]) == [track.id, track.id, track.id, track.id]
    assert length(points) == 4

    log =
      capture_log(fn ->
        for %{"input_distance" => input, "output_distance" => output} <- expected["clamp_cases"] do
          assert Builder.clamp_distance(input) === output, inspect(input)
        end
      end)

    assert log =~ "Track distance 150000000m exceeds maximum (100000000m); capping"

    for %{"distance" => d, "duration" => t, "avg_speed_kmh" => kmh} <- expected["avg_speed_cases"] do
      assert Builder.avg_speed_kmh(d, t) === kmh, inspect({d, t})
    end

    assert [%{"created" => [id], "updated" => [], "destroyed" => []} = payload] = tracks_changed()
    assert id == track.id
    assert {payload["min_ts"], payload["max_ts"]} == {@start, @finish}
  end

  test "insert reuses the winner on a unique collision", %{user: user, points: points} do
    winner = winner!("device-elev")
    other = winner!("other")
    [first, second | _] = points
    rows("UPDATE points SET track_id = $1 WHERE id = $2", [other, second.id])

    assert {:ok, %{id: ^winner, new?: false}} =
             Builder.create_track!(ScratchRepo, user, points, 100.0, skip_segment_detection: true)

    owners = point_track_ids()
    assert owners[first.id] == winner
    assert owners[second.id] == other
    assert Enum.count(owners, fn {_id, track_id} -> track_id == winner end) == 3
    assert rows("SELECT count(*) FROM tracks") == [[2]]
    assert tracks_changed() == []
  end

  test "reuse attaches nothing outside the winner's window", %{user: user, points: points} do
    [first, second, third, _fourth] = points

    [[winner]] =
      rows(
        "INSERT INTO tracks (user_id, tracker_id, start_at, end_at, original_path, distance, duration, avg_speed, " <>
          "created_at, updated_at) VALUES (1, 'device-elev', to_timestamp($1) AT TIME ZONE 'UTC', " <>
          "to_timestamp($2) AT TIME ZONE 'UTC', ST_GeomFromText('LINESTRING(12.3 51.3,12.4 51.4)', 4326), " <>
          "1, 1, 1.0, now(), now()) RETURNING id",
        [first.timestamp, second.timestamp]
      )

    assert {:ok, %{id: ^winner, new?: false}} =
             Builder.create_track!(ScratchRepo, user, [first, third, second], 100.0,
               skip_segment_detection: true
             )

    owners = point_track_ids()
    assert {owners[first.id], owners[second.id], owners[third.id]} == {winner, winner, nil}
  end

  test "a NULL tracker does not reuse an empty-string winner", %{user: user, points: points} do
    winner!("")
    before = point_track_ids()
    untracked = Enum.map(points, &%{&1 | tracker_id: nil})

    log =
      capture_log(fn ->
        assert {:error, :race_lost} =
                 Builder.create_track!(ScratchRepo, user, untracked, 100.0,
                   skip_segment_detection: true
                 )
      end)

    assert log =~ "event=tracks.race_winner_not_visible user_id=1"
    assert point_track_ids() == before
    assert rows("SELECT count(*) FROM tracks") == [[1]]

    rows("DELETE FROM tracks")
    null_winner = winner!(nil)

    assert {:ok, %{id: ^null_winner, new?: false}} =
             Builder.create_track!(ScratchRepo, user, untracked, 100.0,
               skip_segment_detection: true
             )
  end

  test "a detection error keeps the track without segments", %{user: user, points: points} do
    failing = fn repo, _track, _opts -> repo.query!("SELECT 1 / 0", []) end

    log =
      capture_log(fn ->
        assert {:ok, track} =
                 Builder.create_track!(ScratchRepo, user, points, 100.0, detector: failing)

        send(self(), {:track, track.id})
      end)

    assert_received {:track, id}
    assert log =~ "Failed to detect transportation modes for track #{id}"
    assert rows("SELECT count(*) FROM tracks WHERE id = $1", [id]) == [[1]]
    assert rows("SELECT count(*) FROM track_segments") == [[0]]
    assert Enum.all?(points, &(point_track_ids()[&1.id] == id))
    assert [%{"created" => [^id]}] = tracks_changed()
  end

  test "a race lost in a later run rolls back the whole orphan claim" do
    user = user!()
    t = 1_790_900_000
    owner = track!(user.id, nil, t + 120, t + 130)
    first_run = [point!(user.id, t, 12.3731, 51.3397), point!(user.id, t + 60, 12.3735, 51.3399)]
    owned = point!(user.id, t + 120, 12.3739, 51.3401, track_id: owner)

    second_run = [
      point!(user.id, t + 180, 12.3743, 51.3403),
      point!(user.id, t + 240, 12.3747, 51.3405)
    ]

    track!(user.id, "", t + 180, t + 240)

    points =
      Points.load_chunk(ScratchRepo, user.id, t, t + 240, untracked_only: false, import_id: nil)

    {result, log} =
      with_log(fn ->
        Builder.create_from_orphans!(ScratchRepo, user, points, skip_segment_detection: true)
      end)

    assert rows("SELECT count(*) FROM tracks WHERE user_id = $1", [user.id]) == [[2]]
    owners = point_track_ids()
    assert Enum.map(first_run ++ second_run, &owners[&1]) == [nil, nil, nil, nil]
    assert owners[owned] == owner
    assert tracks_changed() == []
    assert result == {:error, :race_lost}
    assert log =~ "event=tracks.race_winner_not_visible user_id=#{user.id}"
  end
end
