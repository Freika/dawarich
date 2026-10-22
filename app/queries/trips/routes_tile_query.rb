# frozen_string_literal: true

module Trips
  class RoutesTileQuery
    class InvalidTileCoordinatesError < StandardError; end

    LAYER_NAME = 'trip_routes'
    EXTENT = Tracks::VectorTileQuery::EXTENT
    BUFFER = Tracks::VectorTileQuery::BUFFER
    MARGIN = Tracks::VectorTileQuery::MARGIN
    UNTRACKED_MARGIN = 1
    FEATURE_LIMIT = Tracks::VectorTileQuery::TRACKS_PER_TILE_LIMIT
    SIMPLIFY_SKIP_ZOOM = Tracks::VectorTileQuery::SIMPLIFY_SKIP_ZOOM
    TILE_PIXELS = Tracks::VectorTileQuery::TILE_PIXELS
    WEB_MERCATOR_WORLD = Tracks::VectorTileQuery::WEB_MERCATOR_WORLD

    # rubocop:disable Naming/MethodParameterName
    def initialize(trip:, z:, x:, y:, timezone:, points_scope:, exclude_windows: [], privacy_zones: [])
      @trip = trip
      @timezone = timezone
      @points_scope = points_scope
      @exclude_windows = exclude_windows.map { |from, to| [from.to_i, to.to_i] }
      @privacy_zones = privacy_zones.map { |zone| zone.to_h.symbolize_keys.slice(:lon, :lat, :radius) }
      @z = parse_integer(z)
      @x = parse_integer(x)
      @y = parse_integer(y)
    end
    # rubocop:enable Naming/MethodParameterName

    def call
      validate_tile_coordinates!

      row = with_statement_timeout { |conn| conn.select_one(tile_sql) }
      Tracks::VectorTileQuery::Result.new(
        tile: row['tile'], feature_count: row['feature_count'].to_i, limit: FEATURE_LIMIT
      )
    end

    def feature_rows
      validate_tile_coordinates!

      with_statement_timeout { |conn| conn.select_all(rows_sql).to_a }
    end

    private

    attr_reader :trip, :z, :x, :y

    def tile_sql
      <<~SQL.squish
        #{with_clause}
        SELECT ST_AsMVT(tile_features.*, #{quote(LAYER_NAME)}, #{EXTENT}, 'geom') AS tile,
          COUNT(*) AS feature_count
        FROM (
          SELECT day, #{mvt_geom('source_geom')} AS geom FROM visible_features
        ) AS tile_features
        WHERE geom IS NOT NULL
      SQL
    end

    def rows_sql
      <<~SQL.squish
        #{with_clause}
        SELECT track_id, day, ST_AsGeoJSON(source_geom) AS geojson, start_timestamp, end_timestamp
        FROM visible_features
      SQL
    end

    def with_clause
      <<~SQL.squish
        WITH candidates AS MATERIALIZED (
          SELECT tracks.id, tracks.original_path,
            EXTRACT(EPOCH FROM tracks.start_at)::bigint AS start_timestamp,
            EXTRACT(EPOCH FROM tracks.end_at)::bigint AS end_timestamp,
            to_char(#{local_date('tracks.start_at')}, 'YYYY-MM-DD') AS start_day,
            (#{rebuild_predicate}) AS rebuild
          FROM (#{tracks_sql}) AS tracks
          WHERE ST_Intersects(tracks.original_path, ST_Transform(#{envelope(MARGIN)}, 4326))
        ), features AS (
          SELECT id AS track_id, start_day AS day, original_path AS source_geom, start_timestamp, end_timestamp
          FROM candidates
          WHERE NOT rebuild
          UNION ALL
          SELECT candidates.id, to_char(day_paths.day, 'YYYY-MM-DD'), #{zone_clip('day_paths.path')},
            day_paths.start_timestamp, day_paths.end_timestamp
          FROM candidates
          JOIN LATERAL (#{day_paths(@points_scope).sql(track_id_sql: 'candidates.id')}) AS day_paths
            ON day_paths.path IS NOT NULL
          WHERE candidates.rebuild
          UNION ALL
          SELECT NULL::bigint, to_char(untracked.day, 'YYYY-MM-DD'), #{zone_clip('untracked.path')},
            untracked.start_timestamp, untracked.end_timestamp
          FROM (#{untracked_day_paths.sql(track_id_sql: nil)}) AS untracked
          WHERE untracked.path IS NOT NULL
        ), visible_features AS (
          SELECT * FROM features
          WHERE source_geom IS NOT NULL
            AND NOT ST_IsEmpty(source_geom)
            AND ST_Intersects(source_geom, ST_Transform(#{envelope(MARGIN)}, 4326))
          LIMIT #{FEATURE_LIMIT}
        )
      SQL
    end

    def tracks_sql
      trip.user.scoped_tracks
          .where('tracks.end_at >= ? AND tracks.start_at <= ?', trip.started_at, trip.ended_at)
          .select(:id, :start_at, :end_at, :original_path)
          .to_sql
    end

    def rebuild_predicate
      return 'true' if trip.multiple_recording_devices?

      conditions = [
        "tracks.start_at < #{quote(trip.started_at)}",
        "tracks.end_at > #{quote(trip.ended_at)}",
        "#{local_date('tracks.start_at')} <> #{local_date('tracks.end_at')}"
      ]
      conditions += @exclude_windows.map do |from, to|
        "(EXTRACT(EPOCH FROM tracks.start_at) <= #{to} AND EXTRACT(EPOCH FROM tracks.end_at) >= #{from})"
      end
      conditions += @privacy_zones.map do |zone|
        "ST_DWithin(tracks.original_path::geography, #{zone_point(zone)}, #{zone[:radius].to_f})"
      end
      conditions.join(' OR ')
    end

    def day_paths(points_scope, segment_sql: nil)
      Trips::DayPathSql.new(points_scope:, timezone: @timezone, excluded_sql:, segment_sql:,
                            gap_seconds: trip.user.safe_settings.minutes_between_routes.to_i * 60)
    end

    def untracked_day_paths
      day_paths(@points_scope.where(track_id: nil), segment_sql: <<~SQL.squish)
        ST_Intersects(ST_MakeLine(previous_position, position), ST_Transform(#{envelope(UNTRACKED_MARGIN)}, 4326))
      SQL
    end

    def excluded_sql
      conditions = @exclude_windows.map { |from, to| "points.timestamp BETWEEN #{from} AND #{to}" }
      conditions += @privacy_zones.map do |zone|
        "ST_DWithin(points.lonlat, #{zone_point(zone)}, #{zone[:radius].to_f})"
      end
      conditions.join(' OR ').presence
    end

    def zone_clip(geometry)
      return geometry if @privacy_zones.empty?

      buffers = @privacy_zones.map { |zone| "ST_Buffer(#{zone_point(zone)}, #{zone[:radius].to_f})::geometry" }
      "ST_Difference(#{geometry}, ST_Union(ARRAY[#{buffers.join(', ')}]))"
    end

    def zone_point(zone)
      "ST_SetSRID(ST_MakePoint(#{zone[:lon].to_f}, #{zone[:lat].to_f}), 4326)::geography"
    end

    def local_date(column)
      "((#{column} AT TIME ZONE 'UTC') AT TIME ZONE #{quote(@timezone)})::date"
    end

    def mvt_geom(geometry)
      "ST_AsMVTGeom(#{simplified_geom(geometry)}, ST_TileEnvelope(#{z}, #{x}, #{y}), #{EXTENT}, #{BUFFER}, true)"
    end

    def simplified_geom(geometry)
      geom = "ST_Transform(#{geometry}, 3857)"
      return geom if z >= SIMPLIFY_SKIP_ZOOM

      "ST_Simplify(#{geom}, #{WEB_MERCATOR_WORLD / (1 << z) / TILE_PIXELS})"
    end

    def envelope(margin)
      "ST_TileEnvelope(#{z}, #{x}, #{y}, margin => #{margin})"
    end

    def quote(value)
      ActiveRecord::Base.connection.quote(value)
    end

    def with_statement_timeout
      conn = Point.connection
      conn.transaction do
        conn.exec_query("SET LOCAL statement_timeout = #{VectorTileTimeout.query_timeout_ms}",
                        'TripRoutesTileQuery Timeout')
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
      raise InvalidTileCoordinatesError if x.negative? || y.negative? || x > max_index || y > max_index
    end
  end
end
