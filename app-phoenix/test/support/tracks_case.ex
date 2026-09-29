defmodule Dawarich.TracksCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  alias Dawarich.ScratchRepo
  alias Dawarich.Tracks.{Builder, Destroy, Points, Settings}

  @chunk_sql """
  WITH bounds AS (
    SELECT COALESCE($1::timestamptz, (SELECT to_timestamp(min(timestamp)) FROM points WHERE user_id = $3)) AS g_start,
           COALESCE($2::timestamptz, CASE WHEN $1::timestamptz IS NULL
             THEN (SELECT to_timestamp(max(timestamp)) FROM points WHERE user_id = $3) ELSE now() END) AS g_end
  ), edges AS (
    SELECT gs AS c_start, LEAST(gs + interval '1 day', b.g_end) AS c_end, b.g_start, b.g_end
    FROM bounds b, generate_series(b.g_start, b.g_end, interval '1 day') AS gs
    WHERE gs < b.g_end
  ), chunks AS (
    SELECT floor(extract(epoch FROM c_start))::bigint AS start_ts,
           floor(extract(epoch FROM c_end))::bigint AS end_ts,
           floor(extract(epoch FROM GREATEST(c_start - interval '6 hours', g_start)))::bigint AS buffer_start_ts,
           floor(extract(epoch FROM LEAST(c_end + interval '6 hours', g_end)))::bigint AS buffer_end_ts
    FROM edges
  )
  SELECT start_ts, end_ts, buffer_start_ts, buffer_end_ts
  FROM chunks c
  WHERE EXISTS (SELECT 1 FROM points p WHERE p.user_id = $3 AND p.timestamp BETWEEN c.buffer_start_ts AND c.buffer_end_ts)
  ORDER BY start_ts
  """

  using do
    quote do
      use Dawarich.JobsCase
      alias Dawarich.Tracks.TracksFixtures
      import Dawarich.TracksCase

      setup do
        Dawarich.TracksCase.truncate!()
      end
    end
  end

  def truncate! do
    ScratchRepo.query!(
      "TRUNCATE tracks, points, track_segments, imports, shared_links RESTART IDENTITY CASCADE",
      [],
      log: false
    )

    :ok
  end

  def tracks_changed do
    ScratchRepo.query!(
      "SELECT payload FROM phoenix.rails_commands WHERE kind = 'tracks_changed' ORDER BY id",
      [],
      log: false
    ).rows
    |> Enum.map(fn [payload] -> payload end)
  end

  @track_columns ~w(tracker_id start_at end_at original_path_wkt distance duration avg_speed elevation_gain
                    elevation_loss elevation_max elevation_min dominant_mode import_id)

  def expected_track(track), do: Enum.map(@track_columns, &track[&1])

  def actual_tracks do
    ScratchRepo.query!(
      "SELECT tracker_id, floor(extract(epoch FROM start_at))::bigint, floor(extract(epoch FROM end_at))::bigint, " <>
        "ST_AsText(original_path), distance, duration, avg_speed, elevation_gain, elevation_loss, " <>
        "elevation_max, elevation_min, dominant_mode, import_id FROM tracks ORDER BY start_at, tracker_id",
      [],
      log: false
    ).rows
  end

  def expected_tracks(expected) do
    expected["tracks"]
    |> Enum.sort_by(&{&1["start_at"], &1["tracker_id"]})
    |> Enum.map(&expected_track/1)
  end

  def identity_of(%{"tracker_id" => tracker_id, "start_at" => start_at, "end_at" => end_at}),
    do: {tracker_id, start_at, end_at}

  def identity_of(nil), do: nil

  def identities do
    ScratchRepo.query!(
      "SELECT id, tracker_id, floor(extract(epoch FROM start_at))::bigint, floor(extract(epoch FROM end_at))::bigint FROM tracks",
      [],
      log: false
    ).rows
    |> Map.new(fn [id, tracker_id, start_at, end_at] -> {id, {tracker_id, start_at, end_at}} end)
  end

  def point_identities do
    ids = identities()
    Map.new(point_track_ids(), fn {point, track_id} -> {point, track_id && ids[track_id]} end)
  end

  def expected_point_identities(expected) do
    Map.new(expected["points"], &{&1["id"], identity_of(&1["track"])})
  end

  def events(identities_by_id) do
    tracks_changed()
    |> Enum.flat_map(fn payload ->
      for action <- ~w(created updated destroyed),
          id <- payload[action],
          do: {action, Map.fetch!(identities_by_id, id)}
    end)
  end

  def expected_events(expected) do
    Enum.map(expected["events"], &{&1["action"], identity_of(&1["track"])})
  end

  def generate_chunks!(user, call) do
    if call["mode"] in ["bulk", "daily"] and not call["untracked_only"],
      do: Destroy.clean_range!(ScratchRepo, user.id, call["start_at"], call["end_at"])

    for [start_ts, end_ts, buffer_start, buffer_end] <- chunks(user, call) do
      ScratchRepo
      |> Points.load_chunk(user.id, buffer_start, buffer_end,
        untracked_only: call["untracked_only"],
        import_id: call["import_id"]
      )
      |> Points.segments(Settings.minutes_between_routes(user))
      |> Enum.filter(fn segment ->
        hd(segment).timestamp <= end_ts and List.last(segment).timestamp >= start_ts and
          Enum.any?(segment, &is_nil(&1.track_id))
      end)
      |> Enum.each(
        &Builder.create_from_orphans!(ScratchRepo, user, &1, claim_all: call["import_id"] != nil)
      )
    end
  end

  defp chunks(user, call) do
    to_time = fn ts -> ts && DateTime.from_unix!(ts) end

    {:ok, rows} =
      ScratchRepo.transaction(fn ->
        ScratchRepo.query!("SELECT set_config('TimeZone', $1, true)", [call["zone"]], log: false)

        ScratchRepo.query!(
          @chunk_sql,
          [to_time.(call["start_at"]), to_time.(call["end_at"]), user.id],
          log: false
        ).rows
      end)

    rows
  end

  def actual_segments do
    ScratchRepo.query!(
      "SELECT s.transportation_mode, floor(extract(epoch FROM s.start_at))::bigint, " <>
        "floor(extract(epoch FROM s.end_at))::bigint, s.start_index, s.end_index, ST_AsText(s.path), " <>
        "s.distance, s.duration, s.avg_speed, s.max_speed, s.confidence, s.confidence_score, s.source, " <>
        "floor(extract(epoch FROM s.corrected_at))::bigint, t.tracker_id, " <>
        "floor(extract(epoch FROM t.start_at))::bigint, floor(extract(epoch FROM t.end_at))::bigint " <>
        "FROM track_segments s JOIN tracks t ON t.id = s.track_id",
      [],
      log: false
    ).rows
    |> Enum.map(fn row ->
      {values, [tracker_id, start_at, end_at]} = Enum.split(row, 14)
      values ++ [{tracker_id, start_at, end_at}]
    end)
    |> Enum.sort()
  end

  @segment_columns ~w(transportation_mode start_at end_at start_index end_index path_wkt distance duration
                      avg_speed max_speed confidence confidence_score source corrected_at)

  def expected_segments(expected) do
    expected["track_segments"]
    |> Enum.map(
      &(Enum.map(@segment_columns, fn column -> &1[column] end) ++ [identity_of(&1["track"])])
    )
    |> Enum.sort()
  end

  def user!(settings \\ %{}) do
    %{rows: [[id]]} =
      ScratchRepo.query!(
        "INSERT INTO users (email, settings, created_at, updated_at) VALUES ($1, $2, now(), now()) RETURNING id",
        ["tracks-#{System.unique_integer([:positive])}@example.test", settings],
        log: false
      )

    Settings.load!(ScratchRepo, id)
  end

  def point!(user_id, timestamp, lon, lat, opts \\ []) do
    %{rows: [[id]]} =
      ScratchRepo.query!(
        "INSERT INTO points (user_id, timestamp, lonlat, tracker_id, track_id, created_at, updated_at) " <>
          "VALUES ($1, $2, ST_SetSRID(ST_MakePoint($3, $4), 4326)::geography, $5, $6, " <>
          "to_timestamp($7::bigint) AT TIME ZONE 'UTC', to_timestamp($7::bigint) AT TIME ZONE 'UTC') RETURNING id",
        [
          user_id,
          timestamp,
          lon,
          lat,
          opts[:tracker_id],
          opts[:track_id],
          Keyword.get(opts, :created_at, timestamp)
        ],
        log: false
      )

    id
  end

  def track!(user_id, tracker_id, start_at, end_at) do
    %{rows: [[id]]} =
      ScratchRepo.query!(
        "INSERT INTO tracks (user_id, tracker_id, start_at, end_at, original_path, distance, duration, avg_speed, " <>
          "created_at, updated_at) VALUES ($1, $2, to_timestamp($3::bigint) AT TIME ZONE 'UTC', " <>
          "to_timestamp($4::bigint) AT TIME ZONE 'UTC', " <>
          "ST_GeomFromText('LINESTRING(12.3731 51.3397,12.3741 51.3407)', 4326), 100, 300, 1.2, now(), now()) RETURNING id",
        [user_id, tracker_id, start_at, end_at],
        log: false
      )

    id
  end

  def track_rows do
    ScratchRepo.query!(
      "SELECT id, tracker_id, start_at, end_at, ST_AsText(original_path), distance, duration, avg_speed, " <>
        "lock_version, updated_at FROM tracks ORDER BY id",
      [],
      log: false
    ).rows
  end

  def point_track_ids do
    ScratchRepo.query!("SELECT id, track_id FROM points ORDER BY id", [], log: false).rows
    |> Map.new(fn [id, track_id] -> {id, track_id} end)
  end
end
