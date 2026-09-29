defmodule Dawarich.Tracks.TracksFixtures do
  @moduledoc false

  @dir "test/fixtures/tracks"
  @tables ~w[tracks track_segments points users imports point_sources]

  def names do
    @dir
    |> Path.join("*.json")
    |> Path.wildcard()
    |> Enum.map(&Path.basename(&1, ".json"))
    |> Enum.sort()
  end

  def read!(name, opts \\ []) do
    @dir |> Path.join(name <> ".json") |> File.read!() |> Jason.decode!(opts)
  end

  def load!(repo, name) do
    fixture = read!(name)
    input = fixture["input"]

    Enum.each(input["users"], &insert_user(repo, name, &1))
    Enum.each(input["point_sources"], &insert_point_source(repo, name, &1))
    Enum.each(input["imports"], &insert_import(repo, name, &1))
    Enum.each(input["tracks"], &insert_track(repo, &1))
    Enum.each(input["points"], &insert_point(repo, &1))
    Enum.each(input["track_segments"], &insert_track_segment(repo, &1))
    advance_sequences!(repo)

    %{expected: fixture["expected"], call: fixture["call"]}
  end

  def input_counts(name) do
    fixture = read!(name)

    Map.new(fixture["input"], fn {table, rows} -> {table, Enum.map(rows, & &1["id"])} end)
  end

  defp advance_sequences!(repo) do
    Enum.each(@tables, fn table ->
      repo.query!(
        "SELECT setval(pg_get_serial_sequence($1, 'id'), " <>
          "GREATEST((SELECT COALESCE(MAX(id), 0) FROM #{table}), 1))",
        [table]
      )
    end)
  end

  defp insert_user(repo, name, row) do
    repo.query!(
      "INSERT INTO users (id, email, settings, created_at, updated_at) " <>
        "VALUES ($1, $2, $3, now() AT TIME ZONE 'UTC', now() AT TIME ZONE 'UTC')",
      [row["id"], "fixture-#{name}-#{row["id"]}@example.test", row["settings"]]
    )
  end

  defp insert_point_source(repo, name, row) do
    digest = :md5 |> :crypto.hash("fixture-#{name}-#{row["id"]}") |> Base.encode16(case: :lower)

    repo.query!(
      "INSERT INTO point_sources (id, tracker_id, digest, created_at, updated_at) " <>
        "VALUES ($1, $2, $3, now() AT TIME ZONE 'UTC', now() AT TIME ZONE 'UTC')",
      [row["id"], row["tracker_id"], digest]
    )
  end

  defp insert_import(repo, name, row) do
    repo.query!(
      "INSERT INTO imports (id, user_id, name, status, source, additional_data_extraction_status, " <>
        "created_at, updated_at) VALUES ($1, $2, $3, $4, $5, $6, now() AT TIME ZONE 'UTC', " <>
        "now() AT TIME ZONE 'UTC')",
      [
        row["id"],
        row["user_id"],
        "fixture-#{name}-#{row["id"]}.gpx",
        row["status"],
        row["source"],
        row["additional_data_extraction_status"]
      ]
    )
  end

  defp insert_point(repo, row) do
    repo.query!(
      "INSERT INTO points (id, timestamp, lonlat, track_id, altitude, altitude_decimal, tracker_id, " <>
        "source_id, user_id, anomaly, import_id, velocity, accuracy, motion_data, created_at, updated_at) " <>
        "VALUES ($1, $2, ST_GeomFromText($3, 4326)::geography, $4, $5, $6::numeric, $7, $8, $9, $10, $11, " <>
        "$12, $13, $14, to_timestamp($15) AT TIME ZONE 'UTC', now() AT TIME ZONE 'UTC')",
      [
        row["id"],
        row["timestamp"],
        row["lonlat_wkt"],
        row["track_id"],
        row["altitude"],
        row["altitude_decimal"] && Decimal.new(row["altitude_decimal"]),
        row["tracker_id"],
        row["source_id"],
        row["user_id"],
        row["anomaly"],
        row["import_id"],
        row["velocity"],
        row["accuracy"],
        row["motion_data"],
        row["created_at"]
      ]
    )
  end

  defp insert_track(repo, row) do
    repo.query!(
      "INSERT INTO tracks (id, user_id, tracker_id, start_at, end_at, original_path, distance, duration, " <>
        "avg_speed, elevation_gain, elevation_loss, elevation_max, elevation_min, dominant_mode, import_id, " <>
        "created_at, updated_at) VALUES ($1, $2, $3, to_timestamp($4) AT TIME ZONE 'UTC', " <>
        "to_timestamp($5) AT TIME ZONE 'UTC', ST_GeomFromText($6, 4326), $7, $8, $9, $10, $11, $12, $13, $14, " <>
        "$15, now() AT TIME ZONE 'UTC', now() AT TIME ZONE 'UTC')",
      [
        row["id"],
        row["user_id"],
        row["tracker_id"],
        row["start_at"],
        row["end_at"],
        row["original_path_wkt"],
        row["distance"],
        row["duration"],
        row["avg_speed"],
        row["elevation_gain"],
        row["elevation_loss"],
        row["elevation_max"],
        row["elevation_min"],
        row["dominant_mode"],
        row["import_id"]
      ]
    )
  end

  defp insert_track_segment(repo, row) do
    repo.query!(
      "INSERT INTO track_segments (id, track_id, transportation_mode, start_at, end_at, start_index, " <>
        "end_index, path, distance, duration, avg_speed, max_speed, confidence, confidence_score, source, " <>
        "corrected_at, created_at, updated_at) VALUES ($1, $2, $3, to_timestamp($4), to_timestamp($5), $6, " <>
        "$7, ST_GeomFromText($8, 4326), $9, $10, $11, $12, $13, $14, $15, to_timestamp($16) AT TIME ZONE 'UTC', " <>
        "now() AT TIME ZONE 'UTC', now() AT TIME ZONE 'UTC')",
      [
        row["id"],
        row["track_id"],
        row["transportation_mode"],
        row["start_at"],
        row["end_at"],
        row["start_index"],
        row["end_index"],
        row["path_wkt"],
        row["distance"],
        row["duration"],
        row["avg_speed"],
        row["max_speed"],
        row["confidence"],
        row["confidence_score"],
        row["source"],
        row["corrected_at"]
      ]
    )
  end
end
