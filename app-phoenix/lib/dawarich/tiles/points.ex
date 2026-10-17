defmodule Dawarich.Tiles.Points do
  @moduledoc false
  alias Dawarich.Tiles.Http
  @world 40_075_016.685578488

  def fetch(user, params) do
    with {:ok, {z, x, y}} <- Http.coords(params),
         {:ok, range} <- Http.range(user, params) do
      {where, args} = Http.point_scope(user, params, range)
      cells = ceil(512 * 1.125 / grid(z)) + 1
      candidates = candidate(z, x, y, where, 0)

      shift =
        cond do
          z == 0 -> 0
          x == 0 -> @world
          x == Integer.pow(2, z) - 1 -> -@world
          true -> 0
        end

      candidates =
        if shift == 0,
          do: candidates,
          else: candidates <> " UNION ALL " <> candidate(z, x, y, where, shift)

      attrs =
        if z >= 5,
          do:
            "MIN(id) AS id, MIN(battery) AS battery, MIN(track_id) AS track_id, MIN(lock_version) AS revision, MIN(altitude) AS altitude, MIN(velocity) AS velocity, MIN(latitude) AS latitude, MIN(longitude) AS longitude,",
          else: ""

      sql = """
      WITH candidates AS (#{candidates}), features AS (
        SELECT COUNT(*) AS count, MIN(timestamp) AS timestamp, MAX(timestamp) AS max_timestamp,
        #{attrs} ST_AsMVTGeom(ST_Centroid(ST_Collect(geom_3857)), ST_TileEnvelope(#{z},#{x},#{y}),4096,256,true) AS geom
        FROM candidates GROUP BY ST_SnapToGrid(geom_3857,#{@world / Integer.pow(2, z) / 512 * grid(z)}) LIMIT #{cells * cells + 1}
      )
      SELECT ST_AsMVT(features.*, 'points',4096,'geom'), coalesce(jsonb_agg(to_jsonb(features) - 'geom'), '[]'::jsonb)
      FROM features WHERE geom IS NOT NULL
      """

      [[tile, features]] = Http.query(sql, args)
      {:ok, tile, features}
    end
  end

  defp grid(z), do: if(z < 14, do: 4, else: 1)

  defp candidate(z, x, y, where, shift) do
    attrs =
      if z >= 5,
        do:
          "p.id, p.battery, p.track_id, p.lock_version, p.altitude, p.velocity, ST_Y(p.lonlat::geometry) AS latitude, ST_X(p.lonlat::geometry) AS longitude,",
        else: ""

    envelope = envelope(z, x, y, shift)

    prefilter =
      if z >= 2, do: "AND p.lonlat && ST_Transform(#{envelope},4326)::geography", else: ""

    geom = "ST_Transform(p.lonlat::geometry,3857)"
    geom = if shift == 0, do: geom, else: "ST_Translate(#{geom},#{-shift},0)"

    "SELECT p.timestamp, #{attrs} #{geom} AS geom_3857 FROM points p WHERE #{where} AND (p.anomaly = false OR p.anomaly IS NULL) AND p.lonlat IS NOT NULL #{prefilter} AND ST_Intersects(p.lonlat::geometry, ST_Transform(#{envelope},4326))"
  end

  defp envelope(z, x, y, 0), do: "ST_TileEnvelope(#{z},#{x},#{y}, margin => 0.0625)"

  defp envelope(z, x, y, _shift) do
    half = @world / 2
    width = @world / Integer.pow(2, z)
    margin = width * 0.0625
    {left, right} = if x == 0, do: {half - margin, half}, else: {-half, -half + margin}
    bottom = max(half - (y + 1) * width - margin, -half)
    top = min(half - y * width + margin, half)
    "ST_MakeEnvelope(#{left},#{bottom},#{right},#{top},3857)"
  end
end
