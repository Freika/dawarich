defmodule Dawarich.Tracks.Invalid do
  @moduledoc false
  defexception message: "track has fewer than two points"
end

defmodule Dawarich.Tracks.Store do
  @moduledoc false

  alias Dawarich.RubyFloat
  alias Dawarich.Tracks.Builder

  @columns "t.id, t.user_id, t.tracker_id, floor(extract(epoch FROM t.start_at))::bigint, " <>
             "floor(extract(epoch FROM t.end_at))::bigint, t.distance, t.duration, t.avg_speed, t.import_id"

  @distance_sql """
  WITH points_with_previous AS (
    SELECT lonlat, LAG(lonlat) OVER (ORDER BY timestamp) AS prev_lonlat
    FROM (SELECT * FROM points WHERE track_id = $1) AS points
  )
  SELECT COALESCE(SUM(ST_Distance(lonlat::geography, prev_lonlat::geography)), 0)
  FROM points_with_previous WHERE prev_lonlat IS NOT NULL
  """

  def columns, do: @columns

  def to_track([
        id,
        user_id,
        tracker_id,
        start_at,
        end_at,
        distance,
        duration,
        avg_speed,
        import_id
      ]) do
    %{
      id: id,
      user_id: user_id,
      tracker_id: tracker_id,
      start_at: start_at,
      end_at: end_at,
      distance: distance,
      duration: duration,
      avg_speed: avg_speed,
      import_id: import_id
    }
  end

  def all(repo, sql, params), do: Enum.map(repo.query!(sql, params, log: false).rows, &to_track/1)

  def get(repo, id, lock \\ false) do
    lock_sql = if lock, do: " FOR UPDATE", else: ""

    case all(repo, "SELECT #{@columns} FROM tracks t WHERE t.id = $1#{lock_sql}", [id]) do
      [track] -> track
      [] -> nil
    end
  end

  def save!(repo, track, attrs, now \\ nil) do
    changed = update_if_changed!(repo, track.id, attrs, now)
    saved = Map.merge(track, Map.new(attrs))
    moved = changed and {saved.start_at, saved.end_at} != {track.start_at, track.end_at}

    if moved and has_points?(repo, track.id),
      do: repo |> recalculate!(saved) |> elem(0),
      else: saved
  end

  def recalculate!(repo, track) do
    points =
      repo.query!(
        "SELECT ST_X(lonlat::geometry), ST_Y(lonlat::geometry) FROM points WHERE track_id = $1 ORDER BY timestamp",
        [track.id],
        log: false
      ).rows

    if length(points) < 2, do: raise(Dawarich.Tracks.Invalid)

    %{rows: [[meters]]} = repo.query!(@distance_sql, [track.id], log: false)

    %{rows: [[min_ts, max_ts]]} =
      repo.query!(
        "SELECT MIN(timestamp), MAX(timestamp) FROM points WHERE track_id = $1",
        [track.id],
        log: false
      )

    distance = RubyFloat.round(meters * 1.0)
    duration = max_ts - min_ts

    attrs = [
      original_path:
        Builder.path_wkt(Enum.map(points, fn [lon, lat] -> %{lon: lon, lat: lat} end)),
      distance: distance,
      duration: duration,
      avg_speed: Builder.avg_speed_kmh(distance, duration)
    ]

    changed = update_if_changed!(repo, track.id, attrs)
    {Map.merge(track, Map.new(attrs)), changed}
  end

  def update_if_changed!(repo, id, attrs, now \\ nil) do
    indexed = Enum.with_index(attrs, 2)

    sets =
      Enum.map_join(indexed, ", ", fn {{column, _}, i} ->
        "#{column} = #{placeholder(column, i)}"
      end)

    distinct =
      Enum.map_join(indexed, " OR ", fn {{column, _}, i} ->
        "#{column} IS DISTINCT FROM #{placeholder(column, i)}"
      end)

    stamp_sql = if now, do: "$#{length(attrs) + 2}", else: "now()"
    params = [id | Keyword.values(attrs)] ++ if(now, do: [DateTime.to_naive(now)], else: [])

    repo.query!(
      "UPDATE tracks SET #{sets}, updated_at = #{stamp_sql}, lock_version = lock_version + 1 " <>
        "WHERE id = $1 AND (#{distinct}) RETURNING id",
      params,
      log: false
    ).rows != []
  end

  defp placeholder(column, index) when column in [:start_at, :end_at],
    do: "(to_timestamp($#{index}::bigint) AT TIME ZONE 'UTC')"

  defp placeholder(:original_path, index), do: "ST_GeomFromText($#{index}, 4326)"
  defp placeholder(_column, index), do: "$#{index}"

  defp has_points?(repo, id) do
    repo.query!("SELECT EXISTS (SELECT 1 FROM points WHERE track_id = $1)", [id], log: false).rows ==
      [[true]]
  end
end
