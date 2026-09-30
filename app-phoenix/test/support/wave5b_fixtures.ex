defmodule Dawarich.Wave5bFixtures do
  @moduledoc false

  @dirs ~w(test/fixtures/geocoding test/fixtures/visits test/fixtures/enhanced_import)
  @ruby_numbers_path "test/fixtures/ruby_numbers.json"
  @table_order ~w(users countries instance_settings imports areas places tags visits points)

  def names do
    @dirs
    |> Enum.flat_map(&Path.wildcard(Path.join(&1, "*.json")))
    |> Kernel.++([@ruby_numbers_path])
    |> Enum.sort()
  end

  def read!(path), do: path |> File.read!() |> Jason.decode!()

  def load!(repo, path) do
    fixture = read!(path)
    input = fixture["input"] || %{}

    row_counts =
      for table <- @table_order, rows = Map.get(input, table), is_list(rows) do
        Enum.each(rows, &insert(table, repo, &1))
        {table, length(rows)}
      end
      |> Map.new()

    advance_sequences!(repo, Map.keys(row_counts))

    %{fixture: fixture, row_counts: row_counts}
  end

  defp insert("users", repo, row) do
    repo.query!(
      "INSERT INTO users (id, email, encrypted_password, settings, created_at, updated_at) " <>
        "VALUES ($1, $2, '', $3, now() AT TIME ZONE 'UTC', now() AT TIME ZONE 'UTC')",
      [
        row["id"],
        row["email"] || "fixture-user-#{row["id"]}@example.test",
        row["settings"] || %{}
      ]
    )
  end

  defp insert("countries", repo, row) do
    repo.query!(
      "INSERT INTO countries (id, name, iso_a2, iso_a3, geom, created_at, updated_at) " <>
        "VALUES ($1, $2, $3, $4, ST_GeomFromText($5, 4326), now() AT TIME ZONE 'UTC', now() AT TIME ZONE 'UTC')",
      [row["id"], row["name"], row["iso_a2"], row["iso_a3"], row["geom_wkt"]]
    )
  end

  defp insert("instance_settings", repo, row) do
    repo.query!(
      "INSERT INTO instance_settings (id, key, value, encrypted_value, created_at, updated_at) " <>
        "VALUES ($1, $2, $3::jsonb, $4, now() AT TIME ZONE 'UTC', now() AT TIME ZONE 'UTC')",
      [row["id"], row["key"], row["value"], row["encrypted_value"]]
    )
  end

  defp insert("imports", repo, row) do
    repo.query!(
      "INSERT INTO imports (id, user_id, name, source, additional_data_extraction_status, " <>
        "additional_data_extraction, raw_data, created_at, updated_at) VALUES " <>
        "($1, $2, $3, $4, $5, $6::jsonb, $7::jsonb, now() AT TIME ZONE 'UTC', now() AT TIME ZONE 'UTC')",
      [
        row["id"],
        row["user_id"],
        row["name"],
        row["source"],
        row["additional_data_extraction_status"],
        encode_jsonb(row["additional_data_extraction"]) || "{}",
        row["raw_data"] || "null"
      ]
    )
  end

  defp insert("areas", repo, row) do
    repo.query!(
      "INSERT INTO areas (id, user_id, name, latitude, longitude, radius, created_at, updated_at) " <>
        "VALUES ($1, $2, $3, $4, $5, $6, now() AT TIME ZONE 'UTC', now() AT TIME ZONE 'UTC')",
      [row["id"], row["user_id"], row["name"], row["latitude"], row["longitude"], row["radius"]]
    )
  end

  defp insert("places", repo, row) do
    {lon, lat} = lonlat_from_wkt(row["lonlat_wkt"])

    repo.query!(
      "INSERT INTO places (id, user_id, name, latitude, longitude, lonlat, source, import_id, " <>
        "name_locked_at, geodata, created_at, updated_at) VALUES " <>
        "($1, $2, $3, $4, $5, ST_GeomFromText($6, 4326)::geography, $7, $8, $9, $10::jsonb, " <>
        "now() AT TIME ZONE 'UTC', now() AT TIME ZONE 'UTC')",
      [
        row["id"],
        row["user_id"],
        row["name"],
        lat,
        lon,
        row["lonlat_wkt"],
        row["source"] || 0,
        row["import_id"],
        clock_timestamp(row["name_locked_at"]),
        encode_jsonb(row["geodata"]) || "{}"
      ]
    )
  end

  defp insert("tags", repo, row) do
    repo.query!(
      "INSERT INTO tags (id, user_id, name, color, privacy_radius_meters, created_at, updated_at) " <>
        "VALUES ($1, $2, $3, $4, $5, now() AT TIME ZONE 'UTC', now() AT TIME ZONE 'UTC')",
      [row["id"], row["user_id"], row["name"], row["color"], row["privacy_radius_meters"]]
    )
  end

  defp insert("visits", repo, row) do
    repo.query!(
      "INSERT INTO visits (id, user_id, area_id, place_id, started_at, ended_at, duration, name, " <>
        "status, confidence, confidence_breakdown, created_at, updated_at) VALUES " <>
        "($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11::jsonb, now() AT TIME ZONE 'UTC', " <>
        "now() AT TIME ZONE 'UTC')",
      [
        row["id"],
        row["user_id"],
        row["area_id"],
        row["place_id"],
        clock_timestamp(row["started_at"]),
        clock_timestamp(row["ended_at"]),
        row["duration"] || 0,
        row["name"] || "Fixture Visit",
        row["status"] || 0,
        row["confidence"],
        encode_jsonb(row["confidence_breakdown"]) || "{}"
      ]
    )
  end

  defp insert("points", repo, row) do
    repo.query!(
      "INSERT INTO points (id, user_id, timestamp, lonlat, accuracy, visit_id, geodata, " <>
        "reverse_geocoded_at, created_at, updated_at, lock_version) VALUES " <>
        "($1, $2, $3, ST_GeomFromText($4, 4326)::geography, $5, $6, $7::jsonb, $8, " <>
        "now() AT TIME ZONE 'UTC', now() AT TIME ZONE 'UTC', 0)",
      [
        row["id"],
        row["user_id"],
        row["timestamp"],
        row["lonlat_wkt"],
        row["accuracy"],
        row["visit_id"],
        encode_jsonb(row["geodata"]) || "{}",
        clock_timestamp(row["reverse_geocoded_at"])
      ]
    )
  end

  # Fixtures record a clock-set field as the literal string "set" (never the
  # actual wall-clock value Rails wrote) so a fixture stays byte-identical
  # across generation runs; the scratch DB only needs *a* timestamp there.
  defp clock_timestamp(nil), do: nil
  defp clock_timestamp(_marker), do: NaiveDateTime.utc_now()

  # Every jsonb column above was captured via Postgres' `::text` cast, so the
  # fixture holds the already-serialized JSON string, not an Elixir map.
  defp encode_jsonb(nil), do: nil
  defp encode_jsonb(value) when is_binary(value), do: value
  defp encode_jsonb(value), do: Jason.encode!(value)

  defp lonlat_from_wkt(nil), do: {nil, nil}

  defp lonlat_from_wkt(wkt) do
    [lon, lat] =
      ~r/POINT\(\s*(-?[\d.]+)\s+(-?[\d.]+)\s*\)/
      |> Regex.run(wkt, capture: :all_but_first)
      |> Enum.map(&String.to_float(if String.contains?(&1, "."), do: &1, else: &1 <> ".0"))

    {lon, lat}
  end

  defp advance_sequences!(repo, tables) do
    Enum.each(tables, fn table ->
      repo.query!(
        "SELECT setval(pg_get_serial_sequence($1, 'id'), " <>
          "GREATEST((SELECT COALESCE(MAX(id), 0) FROM #{table}), 1))",
        [table]
      )
    end)
  end
end
