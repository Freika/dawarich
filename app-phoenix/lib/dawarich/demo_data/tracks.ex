defmodule Dawarich.DemoData.Tracks do
  @moduledoc false
  @modes %{"walk" => 2, "bike" => 4, "drive" => 5, "taxi" => 5, "highway" => 5, "fly" => 8}

  def seed(repo, user, import, anchor, rows) do
    for row <- rows || [], length(row["path_coordinates"] || []) >= 2 do
      coords = row["path_coordinates"]

      path =
        "LINESTRING(" <> Enum.map_join(coords, ",", fn [lat, lon] -> "#{lon} #{lat}" end) <> ")"

      start = anchor + row["starts_offset_seconds"]
      stop = anchor + row["ends_offset_seconds"]
      mode = Map.fetch!(@modes, row["mode"])
      speed = (row["avg_speed_kmh"] || 0) * 1.0

      [[id]] =
        repo.query!(
          """
          INSERT INTO tracks (user_id,start_at,end_at,original_path,distance,avg_speed,duration,elevation_gain,elevation_loss,elevation_max,elevation_min,dominant_mode,tracker_id,demo,created_at,updated_at)
          VALUES ($1,to_timestamp($2::bigint) AT TIME ZONE 'UTC',to_timestamp($3::bigint) AT TIME ZONE 'UTC',ST_GeomFromText($4,4326),$5,$6,$7,0,0,0,0,$8,'demo',true,now(),now()) RETURNING id
          """,
          [
            user,
            start,
            stop,
            path,
            row["distance_meters"],
            Float.round(speed / 3.6, 3),
            row["duration_seconds"],
            mode
          ],
          log: false
        ).rows

      repo.query!(
        """
        INSERT INTO track_segments (track_id,transportation_mode,start_index,end_index,distance,duration,avg_speed,max_speed,confidence,created_at,updated_at)
        VALUES ($1,$2,0,$3,$4,$5,$6,$7,2,now(),now())
        """,
        [
          id,
          mode,
          length(coords) - 1,
          row["distance_meters"],
          row["duration_seconds"],
          speed,
          speed * 1.2
        ],
        log: false
      )

      repo.query!(
        "UPDATE points SET track_id=$1 WHERE user_id=$2 AND import_id=$3 AND track_id IS NULL AND timestamp >= $4 AND timestamp < $5",
        [id, user, import, start, stop],
        log: false
      )
    end
  end
end
