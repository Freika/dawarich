defmodule Dawarich.Wave5bFixtures do
  @moduledoc false

  @dirs ~w(test/fixtures/geocoding test/fixtures/visits test/fixtures/enhanced_import)
  @ruby_numbers_path "test/fixtures/ruby_numbers.json"
  @table_order ~w(users countries instance_settings imports areas places tags taggings visits place_visits notes points)
  @now "now() AT TIME ZONE 'UTC'"

  def names do
    @dirs
    |> Enum.flat_map(&Path.wildcard(Path.join(&1, "*.json")))
    |> Kernel.++([@ruby_numbers_path])
    |> Enum.sort()
  end

  def tables, do: @table_order

  def read!(path), do: path |> File.read!() |> Jason.decode!()

  def load!(repo, path) do
    fixture = read!(path)
    %{fixture: fixture, row_counts: load_input!(repo, fixture["input"] || %{})}
  end

  def load_input!(repo, input) do
    row_counts =
      for table <- @table_order, rows = Map.get(input, table), is_list(rows), into: %{} do
        Enum.each(rows, &insert(table, repo, &1))
        {table, length(rows)}
      end

    advance_sequences!(repo, Map.keys(row_counts))
    row_counts
  end

  defp insert("users", repo, row) do
    repo.query!(
      "INSERT INTO users (id, email, encrypted_password, settings, visits_redetected_at, created_at, updated_at) " <>
        "VALUES ($1, $2, '', $3, $4, #{@now}, #{@now})",
      [
        row["id"],
        row["email"] || "fixture-user-#{row["id"]}@example.test",
        row["settings"] || %{},
        clock(row["visits_redetected_at"])
      ]
    )
  end

  defp insert("countries", repo, row) do
    repo.query!(
      "INSERT INTO countries (id, name, iso_a2, iso_a3, geom, created_at, updated_at) " <>
        "VALUES ($1, $2, $3, $4, ST_GeomFromText($5, 4326), #{@now}, #{@now})",
      [row["id"], row["name"], row["iso_a2"], row["iso_a3"], row["geom_wkt"]]
    )
  end

  defp insert("instance_settings", repo, row) do
    repo.query!(
      "INSERT INTO instance_settings (id, key, value, encrypted_value, created_at, updated_at) " <>
        "VALUES ($1, $2, $3::jsonb, $4, #{@now}, #{@now})",
      [row["id"], row["key"], row["value"], row["encrypted_value"]]
    )
  end

  defp insert("imports", repo, row) do
    repo.query!(
      "INSERT INTO imports (id, user_id, name, source, additional_data_extraction_status, " <>
        "additional_data_extraction, raw_data, created_at, updated_at) VALUES " <>
        "($1, $2, $3, $4, $5, $6::jsonb, $7::jsonb, #{@now}, #{@now})",
      [
        row["id"],
        row["user_id"],
        row["name"],
        row["source"],
        row["additional_data_extraction_status"],
        jsonb(row["additional_data_extraction"]) || "{}",
        row["raw_data"] || "null"
      ]
    )
  end

  defp insert("areas", repo, row) do
    repo.query!(
      "INSERT INTO areas (id, user_id, name, latitude, longitude, radius, created_at, updated_at) " <>
        "VALUES ($1, $2, $3, $4::text::numeric, $5::text::numeric, $6, #{@now}, #{@now})",
      [
        row["id"],
        row["user_id"],
        row["name"],
        text(row["latitude"]),
        text(row["longitude"]),
        row["radius"]
      ]
    )
  end

  defp insert("places", repo, row) do
    {lon, lat} = lonlat_from_wkt(row["lonlat_wkt"])

    repo.query!(
      "INSERT INTO places (id, user_id, name, latitude, longitude, lonlat, city, country, source, import_id, " <>
        "demo, note, geodata, name_locked_at, reverse_geocoded_at, created_at, updated_at) VALUES " <>
        "($1, $2, $3, $4::text::numeric, $5::text::numeric, ST_GeomFromText($6, 4326)::geography, $7, $8, $9, $10, $11, " <>
        "$12, $13::jsonb, $14, $15, #{@now}, #{@now})",
      [
        row["id"],
        row["user_id"],
        row["name"],
        text(row["latitude"] || lat),
        text(row["longitude"] || lon),
        row["lonlat_wkt"],
        row["city"],
        row["country"],
        row["source"] || 0,
        row["import_id"],
        row["demo"] || false,
        row["note"],
        jsonb(row["geodata"]) || "{}",
        clock(row["name_locked_at"]),
        clock(row["reverse_geocoded_at"])
      ]
    )
  end

  defp insert("tags", repo, row) do
    repo.query!(
      "INSERT INTO tags (id, user_id, name, color, privacy_radius_meters, demo, created_at, updated_at) " <>
        "VALUES ($1, $2, $3, $4, $5, $6, #{@now}, #{@now})",
      [
        row["id"],
        row["user_id"],
        row["name"],
        row["color"],
        row["privacy_radius_meters"],
        row["demo"] || false
      ]
    )
  end

  defp insert("taggings", repo, row) do
    repo.query!(
      "INSERT INTO taggings (id, tag_id, taggable_type, taggable_id, created_at, updated_at) " <>
        "VALUES ($1, $2, $3, $4, #{@now}, #{@now})",
      [row["id"], row["tag_id"], row["taggable_type"], row["taggable_id"]]
    )
  end

  defp insert("visits", repo, row) do
    repo.query!(
      "INSERT INTO visits (id, user_id, area_id, place_id, started_at, ended_at, duration, name, status, " <>
        "confidence, confidence_breakdown, detection_version, demo, import_id, deleted_at, created_at, " <>
        "updated_at) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11::jsonb, $12, $13, $14, $15, " <>
        "#{@now}, #{@now})",
      [
        row["id"],
        row["user_id"],
        row["area_id"],
        row["place_id"],
        epoch(row["started_at"]),
        epoch(row["ended_at"]),
        row["duration"] || 0,
        row["name"],
        row["status"] || 0,
        row["confidence"],
        jsonb(row["confidence_breakdown"]) || "{}",
        row["detection_version"],
        row["demo"] || false,
        row["import_id"],
        clock(row["deleted_at"])
      ]
    )
  end

  defp insert("place_visits", repo, row) do
    repo.query!(
      "INSERT INTO place_visits (id, place_id, visit_id, created_at, updated_at) VALUES ($1, $2, $3, #{@now}, #{@now})",
      [row["id"], row["place_id"], row["visit_id"]]
    )
  end

  defp insert("notes", repo, row) do
    repo.query!(
      "INSERT INTO notes (id, user_id, attachable_type, attachable_id, body, noted_at, created_at, updated_at) " <>
        "VALUES ($1, $2, $3, $4, $5, $6, #{@now}, #{@now})",
      [
        row["id"],
        row["user_id"],
        row["attachable_type"],
        row["attachable_id"],
        row["body"],
        epoch(row["noted_at"])
      ]
    )
  end

  defp insert("points", repo, row) do
    repo.query!(
      "INSERT INTO points (id, user_id, timestamp, lonlat, accuracy, anomaly, visit_id, city, country_name, " <>
        "country_id, geodata, reverse_geocoded_at, lock_version, created_at, updated_at) VALUES " <>
        "($1, $2, $3, ST_GeomFromText($4, 4326)::geography, $5, $6, $7, $8, $9, $10, $11::jsonb, $12, $13, " <>
        "#{@now}, #{@now})",
      [
        row["id"],
        row["user_id"],
        row["timestamp"],
        row["lonlat_wkt"],
        row["accuracy"],
        row["anomaly"],
        row["visit_id"],
        row["city"],
        row["country_name"],
        row["country_id"],
        jsonb(row["geodata"]) || "{}",
        clock(row["reverse_geocoded_at"]),
        row["lock_version"] || 0
      ]
    )
  end

  defp clock(nil), do: nil
  defp clock(_marker), do: NaiveDateTime.utc_now()

  defp epoch(nil), do: nil
  defp epoch(seconds), do: seconds |> DateTime.from_unix!() |> DateTime.to_naive()

  defp jsonb(nil), do: nil
  defp jsonb(value) when is_binary(value), do: value
  defp jsonb(value), do: Jason.encode!(value)

  defp text(nil), do: nil
  defp text(value) when is_binary(value), do: value
  defp text(value), do: to_string(value)

  defp lonlat_from_wkt(nil), do: {nil, nil}

  defp lonlat_from_wkt(wkt) do
    [lon, lat] =
      Regex.run(~r/POINT\(\s*(-?[\d.]+)\s+(-?[\d.]+)\s*\)/, wkt, capture: :all_but_first)

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
