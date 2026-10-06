defmodule Dawarich.Tiles.Tracks do
  @moduledoc false
  alias Dawarich.Tiles.Http
  alias Dawarich.MapApi.Segments
  alias Dawarich.RubyInteger
  @world 40_075_016.685578488

  def fetch(user, params) do
    with {:ok, {z, x, y}} <- Http.coords(params), {:ok, range} <- Http.range(user, params) do
      {where, args} = scope(user, params, range)
      envelope = "ST_TileEnvelope(#{z},#{x},#{y}, margin => 0.0625)"

      clipped =
        cond do
          Http.present?(params["import_id"]) ->
            "true"

          range ->
            {from, to} = range

            "(extract(epoch FROM t.start_at) < #{from} OR extract(epoch FROM t.end_at) > #{to}) AND EXISTS(SELECT 1 FROM points WHERE track_id = t.id)"

          true ->
            "false"
        end

      {points, point_args} = Http.point_scope(user, %{}, nil)
      points = shift_args(points, length(args))

      points =
        if range || Http.present?(params["import_id"]),
          do: points <> " AND (p.anomaly = false OR p.anomaly IS NULL)",
          else: points

      history =
        if range, do: "AND p.timestamp BETWEEN #{elem(range, 0)} AND #{elem(range, 1)}", else: ""

      import =
        if Http.present?(params["import_id"]),
          do:
            "AND import_id = #{RubyInteger.to_i(params["import_id"])} AND previous_import_id = #{RubyInteger.to_i(params["import_id"])}",
          else: ""

      path = """
      SELECT ST_LineMerge(ST_Collect(ST_MakeLine(previous_position, position))) AS path,
             MIN(previous_timestamp) AS start_timestamp, MAX(timestamp) AS end_timestamp
      FROM (SELECT p.timestamp, p.import_id, p.lonlat::geometry AS position,
          LAG(p.lonlat::geometry) OVER sequence AS previous_position,
          LAG(p.timestamp) OVER sequence AS previous_timestamp,
          LAG(p.import_id) OVER sequence AS previous_import_id
        FROM points p WHERE #{points} AND p.lonlat IS NOT NULL AND p.track_id = t.id #{history}
        WINDOW sequence AS (ORDER BY p.timestamp,p.id)) q
      WHERE previous_position IS NOT NULL #{import}
      """

      speed = params["speed_coloring"] == "true" and z >= 8

      geometries =
        if speed,
          do: speed_sql(points, history, import, envelope),
          else: """
          SELECT t.id, ST_AsMVTGeom(#{simplify("CASE WHEN t.clipped THEN c.path ELSE t.original_path END", z)}, ST_TileEnvelope(#{z},#{x},#{y}),4096,256,true) AS geom
          FROM candidates t LEFT JOIN clipped_paths c USING(id)
          WHERE NOT t.clipped OR ST_Intersects(c.path,ST_Transform(#{envelope},4326))
          """

      project =
        if speed,
          do: """
          SELECT id, segment_speed, ST_AsMVTGeom(ST_Transform(geom,3857),ST_TileEnvelope(#{z},#{x},#{y}),4096,256,true) AS geom FROM geometries
          """,
          else: "SELECT * FROM geometries"

      limit = if speed, do: 50_001, else: 20_000

      sql = """
      WITH candidates AS MATERIALIZED (
        SELECT t.*, #{clipped} AS clipped FROM tracks t WHERE #{where}
          AND ST_Intersects(t.original_path,ST_Transform(#{envelope},4326))
      ), clipped_paths AS MATERIALIZED (
        SELECT t.id, c.* FROM candidates t JOIN LATERAL (#{path}) c ON c.path IS NOT NULL WHERE t.clipped
      ), geometries AS MATERIALIZED (#{geometries}), projected AS MATERIALIZED (#{project}), features AS (
        SELECT #{properties()}, #{if speed, do: "projected.segment_speed,", else: ""} projected.geom
        FROM projected JOIN candidates t USING(id) LEFT JOIN clipped_paths c USING(id)
        WHERE projected.geom IS NOT NULL AND (NOT t.clipped OR c.path IS NOT NULL)
        ORDER BY t.clipped LIMIT #{limit}
      ) SELECT ST_AsMVT(features.*, 'tracks',4096,'geom'), coalesce(jsonb_agg(to_jsonb(features) - 'geom'),'[]'::jsonb) FROM features
      """

      [[tile, features]] = Http.query(sql, args ++ point_args)

      if speed and length(features) >= limit do
        {:error, 503, "Too many route segments in this tile. Zoom in or shorten the date range."}
      else
        {:ok, tile, features}
      end
    end
  end

  defp scope(user, params, range) do
    {where, args} = {"t.user_id = $1", [user.id]}
    cutoff = Http.window(user)
    {where, args} = Http.bound(where, args, "extract(epoch FROM t.start_at)::bigint", cutoff)

    {where, args} =
      if range,
        do:
          {where <>
             " AND extract(epoch FROM t.end_at)::bigint >= $#{length(args) + 1} AND extract(epoch FROM t.start_at)::bigint <= $#{length(args) + 2}",
           args ++ [elem(range, 0), elem(range, 1)]},
        else: {where, args}

    if Http.present?(params["import_id"]) do
      {where <>
         " AND EXISTS(SELECT 1 FROM points p WHERE p.user_id = $1 AND p.track_id = t.id AND p.import_id = $#{length(args) + 1}#{if cutoff, do: " AND p.timestamp >= #{cutoff}", else: ""})",
       args ++ [RubyInteger.to_i(params["import_id"])]}
    else
      {where, args}
    end
  end

  defp shift_args(sql, offset),
    do: Regex.replace(~r/\$(\d+)/, sql, fn _, n -> "$#{String.to_integer(n) + offset}" end)

  defp simplify(geom, z) do
    transformed = "ST_Transform(#{geom},3857)"

    if z >= 14,
      do: transformed,
      else: "ST_Simplify(#{transformed},#{@world / Integer.pow(2, z) / 512})"
  end

  defp speed_sql(points, history, import, envelope) do
    """
    SELECT id, segment_speed, ST_Collect(geom) AS geom FROM (
      SELECT t.id, ROUND(s.segment_speed::numeric)::double precision AS segment_speed,
        CASE WHEN t.clipped THEN s.path ELSE coalesce(s.path,t.original_path) END AS geom
      FROM candidates t LEFT JOIN LATERAL (
        SELECT ST_MakeLine(previous_position,position) AS path,
          CASE WHEN timestamp > previous_timestamp THEN LEAST(150.0,ST_DistanceSphere(previous_position,position)*3.6/(timestamp-previous_timestamp)) ELSE 0.0 END AS segment_speed
        FROM (SELECT p.timestamp,p.import_id,p.lonlat::geometry AS position,
          LAG(p.timestamp) OVER sequence AS previous_timestamp,
          LAG(p.lonlat::geometry) OVER sequence AS previous_position,
          LAG(p.import_id) OVER sequence AS previous_import_id
          FROM points p WHERE #{points} AND p.lonlat IS NOT NULL AND p.track_id = t.id
            AND p.timestamp BETWEEN extract(epoch FROM t.start_at)::bigint AND extract(epoch FROM t.end_at)::bigint #{history}
          WINDOW sequence AS (ORDER BY p.timestamp,p.id)) q
        WHERE previous_position IS NOT NULL #{import}
      ) s ON true
    ) g WHERE ST_Intersects(geom,ST_Transform(#{envelope},4326)) GROUP BY id,segment_speed
    """
  end

  defp properties do
    mode = Enum.map_join(0..10, " ", fn n -> "WHEN #{n} THEN '#{Segments.mode(n)}'" end)
    emoji = Enum.map_join(0..10, " ", fn n -> "WHEN #{n} THEN '#{Segments.emoji(n)}'" end)

    from =
      "CASE WHEN t.clipped THEN c.start_timestamp ELSE extract(epoch FROM t.start_at)::bigint END"

    to = "CASE WHEN t.clipped THEN c.end_timestamp ELSE extract(epoch FROM t.end_at)::bigint END"

    """
    t.id AS id, '#6366F1' AS color,
    to_char(to_timestamp(#{from}) AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"') AS start_at,
    to_char(to_timestamp(#{to}) AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"') AS end_at,
    #{from} AS start_timestamp, #{to} AS end_timestamp, t.lock_version AS revision,
    CASE WHEN t.clipped THEN ROUND(ST_Length(c.path::geography))::bigint ELSE t.distance END AS distance,
    CASE WHEN t.clipped THEN CASE WHEN c.end_timestamp > c.start_timestamp THEN ST_Length(c.path::geography)*3.6/(c.end_timestamp-c.start_timestamp) ELSE 0 END ELSE t.avg_speed END AS avg_speed,
    CASE WHEN t.clipped THEN c.end_timestamp-c.start_timestamp ELSE t.duration END AS duration,
    CASE t.dominant_mode #{mode} ELSE 'unknown' END AS dominant_mode,
    CASE t.dominant_mode #{emoji} ELSE '❓' END AS dominant_mode_emoji
    """
  end
end
