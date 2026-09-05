# frozen_string_literal: true

# Speed colors need the timestamps of consecutive points, which original_path
# does not contain. Read them only for intersecting tracks when coloring is on.
class Tracks::SpeedVectorTileQuery < Tracks::VectorTileQuery
  class FeatureLimitError < StandardError; end

  MIN_SPEED_ZOOM = 8
  # Combining equal whole-km/h speeds into one multi-line feature per track
  # preserves each segment's speed to 0.5 km/h and avoids repeating popup
  # metadata hundreds of thousands of times over a long date range.
  MAX_SPEED_FEATURES_PER_TILE = 50_000

  def initialize(points_scope:, **options)
    @points_scope = points_scope
    super(**options)
  end

  def call
    super.tap do |result|
      raise FeatureLimitError if z >= MIN_SPEED_ZOOM && result.truncated?
    end
  end

  private

  def tile_feature_limit
    z < MIN_SPEED_ZOOM ? super : MAX_SPEED_FEATURES_PER_TILE + 1
  end

  # Materialize only the small per-segment geometry before the grouping sort;
  # otherwise PostgreSQL carries full original_path copies into that sort.
  def with_clauses
    return super if z < MIN_SPEED_ZOOM

    <<~SQL
      WITH candidates AS MATERIALIZED (
        SELECT * FROM (#{tile_scope.to_sql}) AS tracks
        WHERE ST_Intersects(tracks.original_path, ST_Transform(#{margined_envelope}, 4326))
      ), geometries AS MATERIALIZED (
        SELECT tracks.id,
          ROUND(segments.segment_speed::numeric)::double precision AS segment_speed,
          ST_AsMVTGeom(
            ST_Transform(COALESCE(segments.path, tracks.original_path), 3857),
            ST_TileEnvelope(#{z}, #{x}, #{y}), #{EXTENT}, #{BUFFER}, true
          ) AS geom
        FROM candidates AS tracks
        LEFT JOIN LATERAL (#{segments_sql}) AS segments ON true
      ), grouped_segments AS (
        SELECT id, segment_speed, ST_Collect(geom) AS geom
        FROM geometries WHERE geom IS NOT NULL
        GROUP BY id, segment_speed
        LIMIT #{tile_feature_limit}
      ), features AS (
        SELECT #{property_columns}, grouped_segments.segment_speed, grouped_segments.geom
        FROM grouped_segments JOIN candidates AS tracks USING (id)
      )
    SQL
  end

  # Compute neighbors before clipping: even two off-screen endpoints can have
  # a visible connecting segment. The existing (track_id, timestamp) index
  # supports this scan; no Point objects or raw metadata enter Ruby or JS.
  def segments_sql
    <<~SQL
      SELECT ST_MakeLine(previous_position, position) AS path,
        CASE WHEN timestamp > previous_timestamp THEN
          LEAST(150.0, ST_DistanceSphere(previous_position, position) * 3.6 /
                       (timestamp - previous_timestamp))
        ELSE 0.0 END AS segment_speed
      FROM (
        SELECT points.timestamp, points.lonlat::geometry AS position,
          LAG(points.lonlat::geometry) OVER sequence AS previous_position,
          LAG(points.timestamp) OVER sequence AS previous_timestamp
        FROM (#{point_scope_sql}) AS points
        WHERE points.track_id = tracks.id
          AND points.timestamp BETWEEN EXTRACT(EPOCH FROM tracks.start_at)::bigint AND EXTRACT(EPOCH FROM tracks.end_at)::bigint
        WINDOW sequence AS (ORDER BY points.timestamp, points.id)
      ) AS ordered_points
      WHERE previous_position IS NOT NULL
    SQL
  end

  def point_scope_sql
    @points_scope.except(:select, :order, :includes, :preload, :eager_load)
                 .where.not(lonlat: nil)
                 .select(:id, :track_id, :timestamp, :lonlat).to_sql
  end
end
