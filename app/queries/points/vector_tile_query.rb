# frozen_string_literal: true

class Points::VectorTileQuery
  class InvalidTileCoordinatesError < StandardError; end

  Result = Struct.new(:tile, :feature_count, :limit, keyword_init: true) do
    def truncated?
      feature_count >= limit
    end
  end

  EXTENT = 4096
  BUFFER = 256
  # Candidate rows must cover the ST_AsMVTGeom buffer, or markers clip at tile seams
  MARGIN = (BUFFER.to_f / EXTENT)
  # The z0 world tile's geography bbox does not contain its own planar extent —
  # measured against a 1.5-degree global grid it drops 27k points that the plain
  # intersection keeps, so the prefilter must not run there. z1 measured clean,
  # but each of its tiles still spans a full 180 degrees, where wrap direction
  # is ambiguous in principle; the tier starts at z2 rather than rely on that.
  MIN_PREFILTER_ZOOM = 2
  # Below this zoom tiles carry no per-point attributes: features are
  # centroid+count aggregates, so nothing can be popped up or identified.
  MIN_POINT_ATTRIBUTE_ZOOM = 5
  LAYER_NAME = 'points'
  TILE_PIXELS = 512
  WEB_MERCATOR_WORLD = 40_075_016.685578488
  # Bounds the per-query cost (VectorTileTimeout, ENV-overridable);
  # PgBouncer-safe because SET LOCAL runs inside an explicit transaction
  # (see Visits::Detection::CandidateLoader for the pattern)

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
      limit: tile_feature_limit
    )
  end

  # The features the tile is built from, for specs and diagnostics.
  def feature_rows
    validate_tile_coordinates!

    with_statement_timeout { |conn| conn.select_all(rows_sql).to_a }
  end

  # Display-pixels per decimation cell on 512px tiles. Tiers from the 1M-point
  # benchmark (lib/perf/vector_tile_benchmark.rb): 1px put 243k features/13.5 MB
  # in a dense z11 tile, 4px keeps it ~15k/<1 MB — and a 4px cell is smaller
  # than the 12px circle markers, so nothing visible is lost below z14.
  def grid_px
    z < 14 ? 4 : 1
  end

  # Strictly above the maximum distinct grid cells in a margin-expanded tile —
  # a pure bug-guard; a reachable LIMIT would drop an arbitrary subset of cells.
  def tile_feature_limit
    cells_per_axis = ((TILE_PIXELS * (1 + (2 * MARGIN))) / grid_px).ceil + 1
    (cells_per_axis**2) + 1
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
    Point.sanitize_sql_array(["ST_AsMVT(features.*, ?, #{EXTENT}, 'geom')", LAYER_NAME])
  end

  # One-pass hash aggregation — a DISTINCT ON + window-count variant paid for a
  # full sort (1.3s on a dense z11 tile). MIN() keeps the representative
  # deterministic; count=1 cells are exact, and merged cells never show popups,
  # so mixed MINs are invisible.
  def with_clauses
    <<~SQL
      WITH candidates AS (#{candidates_sql}),
      features AS (
        SELECT COUNT(*) AS count,
          #{point_attribute_aggregates}
          #{mvt_geom_expression('ST_Centroid(ST_Collect(geom_3857))')} AS geom
        FROM candidates
        GROUP BY #{snap_expression}
        LIMIT #{tile_feature_limit}
      )
    SQL
  end

  def point_attribute_aggregates
    return '' unless point_regime?

    <<~SQL.squish
      MIN(id) AS id, MIN(timestamp) AS timestamp, MIN(battery) AS battery,
      MIN(altitude) AS altitude, MIN(velocity) AS velocity,
      MIN(latitude) AS latitude, MIN(longitude) AS longitude,
    SQL
  end

  def point_regime?
    z >= MIN_POINT_ATTRIBUTE_ZOOM
  end

  def prefilterable?
    z >= MIN_PREFILTER_ZOOM
  end

  def candidates_sql
    branches = [candidate_branch_sql(shift: 0)]
    branches << candidate_branch_sql(shift: antimeridian_shift) unless antimeridian_shift.zero?

    branches.join(' UNION ALL ')
  end

  # Edge tiles (x = 0/max) have buffer bands beyond the antimeridian: a wrapped
  # branch finds those points and translates them into the tile's frame. The
  # shift preserves grid alignment (cell size divides the world width exactly).
  def antimeridian_shift
    return 0 if z.zero?

    max_index = (1 << z) - 1
    return WEB_MERCATOR_WORLD if x.zero?
    return -WEB_MERCATOR_WORLD if x == max_index

    0
  end

  def candidate_branch_sql(shift:)
    columns =
      if point_regime?
        <<~SQL.squish
          points.id AS id, points.timestamp AS timestamp, points.battery AS battery,
          points.altitude AS altitude, points.velocity AS velocity,
          ST_Y(points.lonlat::geometry) AS latitude,
          ST_X(points.lonlat::geometry) AS longitude,
        SQL
      else
        ''
      end

    <<~SQL.squish
      SELECT #{columns}
        #{translated_geom_expression(shift)} AS geom_3857
      FROM (#{tile_scope.to_sql}) AS points
      WHERE points.lonlat IS NOT NULL
        #{spatial_prefilter(shift)}
        AND ST_Intersects(
          points.lonlat::geometry,
          ST_Transform(#{margined_envelope(shift)}, 4326)
        )
    SQL
  end

  def translated_geom_expression(shift)
    geom = 'ST_Transform(points.lonlat::geometry, 3857)'
    return geom if shift.zero?

    "ST_Translate(#{geom}, #{-shift}, 0)"
  end

  # ST_TileEnvelope clamps its margin at the world bound — edge tiles get NO
  # buffer past the antimeridian. The wrapped branch searches a hand-built seam
  # band instead, kept inside the mercator domain so its 4326 transform never
  # yields |lon| > 180 (a geography cast of that would wrap unpredictably).
  def margined_envelope(shift)
    return "ST_TileEnvelope(#{z}, #{x}, #{y}, margin => #{MARGIN})" if shift.zero?

    seam_band_envelope
  end

  def seam_band_envelope
    half = WEB_MERCATOR_WORLD / 2
    tile_width = WEB_MERCATOR_WORLD / (1 << z)
    margin_meters = tile_width * MARGIN
    y_max = [half - (y * tile_width) + margin_meters, half].min
    y_min = [half - ((y + 1) * tile_width) - margin_meters, -half].max

    if x.zero? # the west buffer wraps to the far east of the world
      "ST_MakeEnvelope(#{half - margin_meters}, #{y_min}, #{half}, #{y_max}, 3857)"
    else # the east buffer wraps to the far west
      "ST_MakeEnvelope(#{-half}, #{y_min}, #{-half + margin_meters}, #{y_max}, 3857)"
    end
  end

  # lonlat is geography, so the planar test alone cannot use the GiST index
  def spatial_prefilter(shift)
    return '' unless prefilterable?

    "AND points.lonlat && ST_Transform(#{margined_envelope(shift)}, 4326)::geography"
  end

  def snap_expression
    "ST_SnapToGrid(geom_3857, #{cell_size})"
  end

  def mvt_geom_expression(geom)
    "ST_AsMVTGeom(#{geom}, ST_TileEnvelope(#{z}, #{x}, #{y}), #{EXTENT}, #{BUFFER}, true)"
  end

  def cell_size
    WEB_MERCATOR_WORLD / (1 << z) / TILE_PIXELS * grid_px
  end

  def tile_scope
    scope.except(:select, :order, :includes, :preload, :eager_load)
         .select(:id, :timestamp, :battery, :altitude, :velocity, :lonlat)
  end

  def with_statement_timeout
    conn = Point.connection
    conn.transaction do
      conn.exec_query("SET LOCAL statement_timeout = #{VectorTileTimeout.query_timeout_ms}",
                      'VectorTileQuery Timeout')
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
