defmodule Dawarich.TracksCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  alias Dawarich.{Redis, ScratchRepo}
  alias Dawarich.Tracks.{ChunkWorker, RangeWorker, Settings}

  @oban Dawarich.TracksCase.Oban

  using do
    quote do
      use Dawarich.JobsCase
      alias Dawarich.Tracks.TracksFixtures
      import Dawarich.TracksCase

      setup do
        Dawarich.TracksCase.truncate!()
        Dawarich.TracksCase.start_services!()
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

  def oban, do: @oban

  def start_services! do
    Dawarich.JobsCase.start_oban(@oban)
    ExUnit.Callbacks.start_supervised!(hd(Redis.child_specs()))
    {:ok, "OK"} = Redis.command(["FLUSHDB"])
    :ok
  end

  def rails_redis! do
    config = Application.fetch_env!(:dawarich, :redis)
    {:ok, conn} = Redix.start_link(config[:url], database: config[:database])
    conn
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
    id = Ecto.UUID.generate()

    :ok =
      RangeWorker.run(ScratchRepo, @oban, %{
        "event_id" => id,
        "user_id" => user.id,
        "start_at" => iso(call["start_at"]),
        "end_at" => iso(call["end_at"]),
        "time_zone" => call["zone"],
        "mode" => call["mode"],
        "untracked_only" => call["untracked_only"],
        "import_id" => call["import_id"],
        "low_priority" => false
      })

    for [args] <- chunk_jobs(id), do: :ok = ChunkWorker.run(ScratchRepo, @oban, args)
    id
  end

  def chunk_jobs(generation_id) do
    ScratchRepo.query!(
      "SELECT args FROM oban.oban_jobs WHERE worker = $1 AND args->>'generation_id' = $2 " <>
        "ORDER BY (args->>'chunk_id')::int",
      [inspect(ChunkWorker), generation_id],
      log: false
    ).rows
  end

  def iso(nil), do: nil

  def iso(epoch),
    do: epoch |> DateTime.from_unix!() |> Map.put(:microsecond, {0, 6}) |> DateTime.to_iso8601()

  def generation(id) do
    ScratchRepo.query!(
      "SELECT status, total_chunks, completed_chunks, poll_count, stall_count, error " <>
        "FROM phoenix.track_generations WHERE id = $1",
      [Ecto.UUID.dump!(id)],
      log: false
    ).rows
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
