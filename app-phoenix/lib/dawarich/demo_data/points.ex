defmodule Dawarich.DemoData.Points do
  @moduledoc false

  def seed(repo, user, id, anchor, fixture) do
    {:ok, seed, _} = DateTime.from_iso8601(fixture["seed_date"])
    delta = anchor - DateTime.to_unix(seed)

    rows =
      Enum.map(fixture["features"], fn feature ->
        p = feature["properties"]

        p =
          Map.update(p, "battery_status", nil, fn
            value when is_binary(value) ->
              Map.fetch!(
                %{
                  "unknown" => 0,
                  "unplugged" => 1,
                  "charging" => 2,
                  "full" => 3,
                  "connected_not_charging" => 4,
                  "discharging" => 5
                },
                value
              )

            value ->
              value
          end)

        Map.merge(p, %{"timestamp" => p["timestamp"] + delta})
      end)

    for batch <- Enum.chunk_every(rows, 1000) do
      repo.query!(
        """
        INSERT INTO points (user_id,import_id,timestamp,lonlat,altitude,velocity,accuracy,vertical_accuracy,battery,battery_status,tracker_id,raw_data,inrids,in_regions,geodata,created_at,updated_at)
        SELECT $1,$2,p.timestamp,ST_SetSRID(ST_MakePoint(p.longitude::float8,p.latitude::float8),4326),p.altitude,p.velocity,p.accuracy,p.vertical_accuracy,p.battery,p.battery_status,'demo','{}','{}','{}','{}',now(),now()
        FROM jsonb_to_recordset($3::jsonb) AS p(timestamp integer,longitude text,latitude text,altitude integer,velocity text,accuracy integer,vertical_accuracy integer,battery integer,battery_status integer)
        ON CONFLICT DO NOTHING
        """,
        [user, id, batch],
        log: false
      )
    end

    repo.query!(
      """
      WITH bounds AS MATERIALIZED (
        SELECT ST_SetSRID(ST_Extent(lonlat::geometry)::geometry,4326) AS geom FROM points WHERE import_id=$1
      ), country_parts AS MATERIALIZED (
        SELECT countries.id, part.geom FROM countries JOIN bounds ON countries.geom && bounds.geom
        CROSS JOIN LATERAL ST_Subdivide(countries.geom,256) AS part(geom)
        WHERE part.geom && bounds.geom
      )
      UPDATE points SET country_id=country_parts.id FROM country_parts
      WHERE points.import_id=$1 AND points.country_id IS NULL
        AND country_parts.geom && points.lonlat::geometry AND ST_Intersects(country_parts.geom,points.lonlat::geometry)
      """,
      [id],
      log: false
    )
  end
end
