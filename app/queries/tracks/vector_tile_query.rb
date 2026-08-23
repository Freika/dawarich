# frozen_string_literal: true

class Tracks::VectorTileQuery
  class InvalidTileCoordinatesError < StandardError; end

  Result = Struct.new(:tile, :feature_count, :limit, keyword_init: true) do
    def truncated?
      feature_count >= limit
    end
  end

  EXTENT = 4096
  BUFFER = 256
  # Candidate rows must cover the ST_AsMVTGeom buffer, or lines clip at tile seams
  MARGIN = (BUFFER.to_f / EXTENT)
  LAYER_NAME = 'tracks'
  TILE_PIXELS = 512
  WEB_MERCATOR_WORLD = 40_075_016.685578488
  # Bounds the per-query cost (VectorTileTimeout, ENV-overridable);
  # PgBouncer-safe because SET LOCAL runs inside an explicit transaction
  # (same pattern as Points::VectorTileQuery).
  # Above any plausible tracks-in-one-tile count. The benchmark proved 2,000 is
  # REACHABLE (a 3,400-track city account puts ~2,900 in its home tile), so the
  # guard sits an order of magnitude above the densest measured case.
  TRACKS_PER_TILE_LIMIT = 20_000
  # At and above this zoom the simplify call is skipped entirely — ST_AsMVTGeom's
  # extent quantization is the only reduction (running DP with tolerance 0 would
  # still pay the full pass for nothing). Plain ST_Simplify, NOT
  # PreserveTopology: real tracks self-cross, and the topology variant refuses
  # to drop those vertices — benchmark measured 781 KB vs 110 KB on the dense
  # z8 tile for identical visual output. A sub-pixel track collapsing to
  # nothing at coarse zoom is correct, matching the points quantization.
  SIMPLIFY_SKIP_ZOOM = 14

  def initialize(scope:, z:, x:, y:) # rubocop:disable Naming/MethodParameterName
    @scope = scope
    @z = parse_integer(z)
    @x = parse_integer(x)
    @y = parse_integer(y)
  end

  def call
    validate_tile_coordinates!

    row = with_statement_timeout { |conn| conn.select_one(tile_sql) }

    Result.new(
      tile: row['tile'],
      feature_count: row['feature_count'].to_i,
      limit: TRACKS_PER_TILE_LIMIT
    )
  end

  # The features the tile is built from, for specs and diagnostics.
  def feature_rows
    validate_tile_coordinates!

    with_statement_timeout { |conn| conn.select_all(rows_sql).to_a }
  end

  private

  attr_reader :scope, :z, :x, :y

  # z/x/y are validated Integers and every other interpolated value is program-
  # computed — the only user-influenced SQL is the tile_scope relation.
  def tile_sql
    <<~SQL.squish
      #{with_clauses}
      SELECT #{sanitized_mvt_call} AS tile, COUNT(*) AS feature_count
      FROM features
      WHERE geom IS NOT NULL
    SQL
  end

  def rows_sql
    <<~SQL.squish
      #{with_clauses}
      SELECT * FROM features WHERE geom IS NOT NULL
    SQL
  end

  def sanitized_mvt_call
    Track.sanitize_sql_array(["ST_AsMVT(features.*, ?, #{EXTENT}, 'geom')", LAYER_NAME])
  end

  # No decimation and no wrapped antimeridian branch: tracks are thousands per
  # account, and a seam-crossing linestring renders exactly as classic GeoJSON
  # does today (a world-spanning planar line) — translating the whole line
  # would move half its vertices wrongly.
  def with_clauses
    <<~SQL
      WITH features AS (
        SELECT #{property_columns},
          #{mvt_geom_expression} AS geom
        FROM (#{tile_scope.to_sql}) AS tracks
        WHERE ST_Intersects(
          tracks.original_path,
          ST_Transform(#{margined_envelope}, 4326)
        )
        LIMIT #{TRACKS_PER_TILE_LIMIT}
      )
    SQL
  end

  # The exact scalar property set (keys AND types) of
  # Tracks::GeojsonSerializer#base_properties + dominant_mode fields, so JS
  # click/popup/animation flows are source-agnostic. mode_timeline/segments are
  # arrays — MVT cannot carry them; the segments flow fetches by id instead.
  def property_columns
    <<~SQL.squish
      tracks.id AS id,
      #{Track.sanitize_sql_array(['? AS color', Tracks::GeojsonSerializer::DEFAULT_COLOR])},
      to_char(tracks.start_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS start_at,
      to_char(tracks.end_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS end_at,
      tracks.distance AS distance,
      tracks.avg_speed AS avg_speed,
      tracks.duration AS duration,
      #{mode_case_expression} AS dominant_mode,
      #{emoji_case_expression} AS dominant_mode_emoji
    SQL
  end

  def mode_case_expression
    whens = Track::TRANSPORTATION_MODES.map do |name, value|
      Track.sanitize_sql_array(['WHEN ? THEN ?', value, name.to_s])
    end
    "CASE tracks.dominant_mode #{whens.join(' ')} ELSE 'unknown' END"
  end

  def emoji_case_expression
    whens = Track::TRANSPORTATION_MODES.map do |name, value|
      emoji = Tracks::GeojsonSerializer::MODE_EMOJIS.fetch(name.to_s, '❓')
      Track.sanitize_sql_array(['WHEN ? THEN ?', value, emoji])
    end
    "CASE tracks.dominant_mode #{whens.join(' ')} ELSE '❓' END"
  end

  def mvt_geom_expression
    "ST_AsMVTGeom(#{simplified_geom}, ST_TileEnvelope(#{z}, #{x}, #{y}), #{EXTENT}, #{BUFFER}, true)"
  end

  def simplified_geom
    geom = 'ST_Transform(tracks.original_path, 3857)'
    return geom if z >= SIMPLIFY_SKIP_ZOOM

    "ST_Simplify(#{geom}, #{simplify_tolerance})"
  end

  # One display pixel in meters at this zoom (Task 8 benchmark tunes the
  # variant and value; ST_AsMVTGeom's quantization handles the rest).
  def simplify_tolerance
    WEB_MERCATOR_WORLD / (1 << z) / TILE_PIXELS
  end

  def margined_envelope
    "ST_TileEnvelope(#{z}, #{x}, #{y}, margin => #{MARGIN})"
  end

  def tile_scope
    scope.except(:select, :order, :includes, :preload, :eager_load)
         .select(:id, :start_at, :end_at, :distance, :avg_speed, :duration,
                 :dominant_mode, :original_path)
  end

  def with_statement_timeout
    conn = Track.connection
    conn.transaction do
      conn.exec_query("SET LOCAL statement_timeout = #{VectorTileTimeout.query_timeout_ms}",
                      'TracksVectorTileQuery Timeout')
      yield conn
    end
  end

  def parse_integer(value)
    return value if value.is_a?(Integer)

    Integer(value, 10)
  rescue ArgumentError, TypeError
    raise InvalidTileCoordinatesError
  end

  def validate_tile_coordinates!
    raise InvalidTileCoordinatesError if z.negative? || z > 22

    max_index = (1 << z) - 1
    raise InvalidTileCoordinatesError if x.negative? || y.negative?
    raise InvalidTileCoordinatesError if x > max_index || y > max_index
  end
end
