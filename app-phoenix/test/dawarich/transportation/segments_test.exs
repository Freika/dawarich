defmodule Dawarich.Transportation.SegmentsTest do
  use Dawarich.JobsCase

  alias Dawarich.Tracks.TracksFixtures
  alias Dawarich.Transportation.Segments

  setup do
    ScratchRepo.query!(
      "TRUNCATE tracks, points, track_segments, imports RESTART IDENTITY CASCADE",
      [],
      log: false
    )

    :ok
  end

  test "reclassification reproduces Rails' segments and dominant mode" do
    %{expected: expected} = TracksFixtures.load!(ScratchRepo, "transport_reclassify")
    expected_track = List.first(expected["tracks"])
    track_id = expected_track["id"]
    settings = user_settings(track_id)

    {:ok, mode} =
      ScratchRepo.transaction(fn ->
        Segments.reclassify!(ScratchRepo, track_id, settings, fallback: false)
      end)

    assert Segments.mode_to_int(mode) == expected_track["dominant_mode"]
    assert load_track(track_id).dominant_mode == expected_track["dominant_mode"]

    actual_segments = track_id |> load_segments() |> Enum.sort_by(& &1.start_at)
    expected_segments = Enum.sort_by(expected["track_segments"], & &1["start_at"])

    assert length(actual_segments) == length(expected_segments)

    actual_segments
    |> Enum.zip(expected_segments)
    |> Enum.each(fn {actual, exp} -> assert_segment(actual, exp) end)

    corrected = Enum.find(actual_segments, &(&1.corrected_at == 1_796_104_800))
    assert corrected.transportation_mode == 4
    assert corrected.start_at == 1_796_108_520
    assert corrected.distance == 400
  end

  test "anchor_now anchors a legacy index-only correction" do
    TracksFixtures.load!(ScratchRepo, "transport_reclassify")

    ScratchRepo.transaction(fn ->
      assert Segments.anchor_now!(ScratchRepo, [2]) == :ok
    end)

    [row] = load_segments_by_id([2])
    assert row.start_at == 1_796_108_400
    assert row.end_at == 1_796_108_460
    assert row.path_wkt == "LINESTRING(12.3731 51.3397,12.37311 51.33971,12.37312 51.33972)"
  end

  test "anchor_now falls back to per-row anchoring when duplicate removal leaves a collision" do
    result =
      ScratchRepo.transaction(fn ->
        base_ts = 2_000_000_000
        {user_id, track_id} = insert_user_and_track(base_ts)
        insert_points(track_id, user_id, base_ts)

        anchored_id =
          insert_segment(track_id, %{
            start_at: base_ts,
            end_at: base_ts + 60,
            start_index: nil,
            end_index: nil
          })

        a_id = insert_index_only_segment(track_id, 0, 2)
        b_id = insert_index_only_segment(track_id, 3, 5)

        assert Segments.anchor_now!(ScratchRepo, [a_id, b_id]) == :ok

        a = a_id |> List.wrap() |> load_segments_by_id() |> List.first()
        b = b_id |> List.wrap() |> load_segments_by_id() |> List.first()
        anchored = anchored_id |> List.wrap() |> load_segments_by_id() |> List.first()

        assert is_nil(a.start_at)
        assert b.start_at == base_ts + 90
        assert b.end_at == base_ts + 150
        assert b.path_wkt |> String.split(",") |> length() == 3
        assert anchored.start_at == base_ts
        assert anchored.end_at == base_ts + 60

        assert ScratchRepo.query!("SELECT 1", [], log: false).rows == [[1]]

        :ok
      end)

    assert {:ok, :ok} = result
  end

  test "pick_dominant_mode keeps first-seen order on ties" do
    segments = [
      %{transportation_mode: "driving", distance: 5000, duration: 600},
      %{transportation_mode: "train", distance: 5000, duration: 600}
    ]

    assert Segments.pick_dominant_mode(segments) == "driving"
  end

  defp insert_user_and_track(base_ts) do
    [[user_id]] =
      ScratchRepo.query!(
        "INSERT INTO users (email, settings, created_at, updated_at) VALUES ($1, '{}', now(), now()) " <>
          "RETURNING id",
        ["scratch-anchor-#{System.unique_integer([:positive])}@example.test"],
        log: false
      ).rows

    [[track_id]] =
      ScratchRepo.query!(
        "INSERT INTO tracks (user_id, tracker_id, start_at, end_at, original_path, created_at, updated_at) " <>
          "VALUES ($1, 'anchor-test', to_timestamp($2), to_timestamp($3), " <>
          "ST_GeomFromText('LINESTRING(12.3731 51.3397, 12.3741 51.3407)', 4326), now(), now()) RETURNING id",
        [user_id, base_ts, base_ts + 150],
        log: false
      ).rows

    {user_id, track_id}
  end

  defp insert_points(track_id, user_id, base_ts) do
    for i <- 0..5 do
      lon = 12.3731 + i * 0.0001
      lat = 51.3397 + i * 0.0001

      ScratchRepo.query!(
        "INSERT INTO points (timestamp, lonlat, track_id, user_id, created_at, updated_at) " <>
          "VALUES ($1, ST_GeomFromText($2, 4326)::geography, $3, $4, now(), now())",
        [base_ts + i * 30, "POINT(#{lon} #{lat})", track_id, user_id],
        log: false
      )
    end
  end

  defp insert_segment(track_id, %{
         start_at: start_at,
         end_at: end_at,
         start_index: si,
         end_index: ei
       }) do
    [[id]] =
      ScratchRepo.query!(
        "INSERT INTO track_segments (track_id, transportation_mode, start_at, end_at, start_index, " <>
          "end_index, created_at, updated_at) VALUES ($1, 5, to_timestamp($2), to_timestamp($3), $4, $5, " <>
          "now(), now()) RETURNING id",
        [track_id, start_at, end_at, si, ei],
        log: false
      ).rows

    id
  end

  defp insert_index_only_segment(track_id, start_index, end_index) do
    [[id]] =
      ScratchRepo.query!(
        "INSERT INTO track_segments (track_id, transportation_mode, start_index, end_index, created_at, " <>
          "updated_at) VALUES ($1, 5, $2, $3, now(), now()) RETURNING id",
        [track_id, start_index, end_index],
        log: false
      ).rows

    id
  end

  defp load_track(track_id) do
    [[dominant_mode]] =
      ScratchRepo.query!("SELECT dominant_mode FROM tracks WHERE id = $1", [track_id], log: false).rows

    %{dominant_mode: dominant_mode}
  end

  defp user_settings(track_id) do
    [[user_id]] =
      ScratchRepo.query!("SELECT user_id FROM tracks WHERE id = $1", [track_id], log: false).rows

    [[settings]] =
      ScratchRepo.query!("SELECT settings FROM users WHERE id = $1", [user_id], log: false).rows

    settings
  end

  defp load_segments(track_id) do
    query_segments("WHERE track_id = $1", [track_id])
  end

  defp load_segments_by_id(ids) do
    query_segments("WHERE id = ANY($1::bigint[]) ORDER BY id", [ids])
  end

  defp query_segments(where_clause, params) do
    result =
      ScratchRepo.query!(
        "SELECT transportation_mode, EXTRACT(EPOCH FROM start_at)::bigint, " <>
          "EXTRACT(EPOCH FROM end_at)::bigint, start_index, end_index, ST_AsText(path), distance, " <>
          "duration, avg_speed, max_speed, confidence, confidence_score, source, " <>
          "EXTRACT(EPOCH FROM corrected_at)::bigint FROM track_segments #{where_clause}",
        params,
        log: false
      )

    Enum.map(result.rows, &row_to_segment/1)
  end

  defp row_to_segment([
         mode,
         start_at,
         end_at,
         si,
         ei,
         path,
         distance,
         duration,
         avg_speed,
         max_speed,
         confidence,
         confidence_score,
         source,
         corrected_at
       ]) do
    %{
      transportation_mode: mode,
      start_at: start_at,
      end_at: end_at,
      start_index: si,
      end_index: ei,
      path_wkt: path,
      distance: distance,
      duration: duration,
      avg_speed: avg_speed,
      max_speed: max_speed,
      confidence: confidence,
      confidence_score: confidence_score,
      source: source,
      corrected_at: corrected_at
    }
  end

  defp assert_segment(actual, exp) do
    assert actual.transportation_mode == exp["transportation_mode"]
    assert actual.start_at == exp["start_at"]
    assert actual.end_at == exp["end_at"]
    assert actual.start_index == exp["start_index"]
    assert actual.end_index == exp["end_index"]
    assert actual.path_wkt == exp["path_wkt"]
    assert actual.distance == exp["distance"]
    assert actual.duration == exp["duration"]
    assert_close_float(actual.avg_speed, exp["avg_speed"])
    assert_close_float(actual.max_speed, exp["max_speed"])
    assert actual.confidence == exp["confidence"]
    assert_close_float(actual.confidence_score, exp["confidence_score"])
    assert actual.source == exp["source"]
    assert actual.corrected_at == exp["corrected_at"]
  end

  defp assert_close_float(nil, nil), do: :ok

  defp assert_close_float(actual, expected) do
    assert abs(actual - expected) <= max(abs(expected) * 1.0e-9, 1.0e-9)
  end
end
