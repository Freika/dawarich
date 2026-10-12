# frozen_string_literal: true

module Achievements
  # Shared, cached SVG geometry for the whole collection, earned or locked.
  class RegionSilhouettes
    TOLERANCE = 0.02

    CACHE_VERSION = 3
    CACHE_TTL = 1.week

    SOURCES = {
      subdivision: { table: 'regions', column: 'code' },
      country: { table: 'countries', column: 'iso_a2' }
    }.freeze

    # Artwork framing only: never change the boundaries used to award visits.
    # Select whole polygons, preserving nearby islands (e.g. Corsica/Balearics).
    # Do not use a generic "largest polygon" rule: it destroys archipelagos.
    COUNTRY_FRAMES = {
      'FR' => [-6, 41, 10, 52],
      'PT' => [-10, 36, -6, 43],
      'NO' => [3, 57, 34, 72],
      'NL' => [3, 50, 8, 54],
      'ES' => [-10, 35, 5, 44.5]
    }.freeze

    # A continent's membership includes entire countries, but its illustration
    # is a regional atlas window, not every overseas possession of its members.
    COLLECTION_FRAMES = { 'continent_europe' => [-25, 34, 60, 72] }.freeze

    def self.collection(codes:, key: nil)
      new(level: :country, codes: codes).collection(key: key)
    end

    def collection(key: nil)
      return nil if @codes.empty?

      digest = Digest::SHA256.hexdigest(@codes.sort.join('/'))
      Rails.cache.fetch("#{cache_key('collection')}/#{key}/#{digest}", expires_in: CACHE_TTL) do
        build_shapes(collection_sql(key)).fetch('collection', false)
      end || nil
    end

    def initialize(level:, codes:)
      @level = level
      @source = SOURCES[level]
      @codes = codes
    end

    def call
      return {} if @source.nil? || @codes.empty?

      cached = Rails.cache.read_multi(*@codes.map { |code| cache_key(code) })
      missing = @codes.reject { |code| cached.key?(cache_key(code)) }
      built = missing.empty? ? {} : build(missing)

      missing.each { |code| Rails.cache.write(cache_key(code), built[code] || false, expires_in: CACHE_TTL) }

      @codes.each_with_object({}) do |code, shapes|
        shape = built[code] || cached[cache_key(code)]
        shapes[code] = shape if shape
      end
    end

    private

    def cache_key(code)
      "achievements/silhouette/v#{CACHE_VERSION}/#{@level}/#{code}"
    end

    def build(codes)
      build_shapes(sql(codes))
    end

    def build_shapes(query)
      ApplicationRecord.connection.select_rows(query).each_with_object({}) do |row, shapes|
        code, path, xmin, ymin, xmax, ymax = row
        width = xmax.to_f - xmin.to_f
        height = ymax.to_f - ymin.to_f
        next if path.blank? || width.zero? || height.zero?

        # ST_AsSVG emits Y negated (SVG's axis points down), so the viewBox
        # starts at -ymax rather than ymin.
        viewbox = [xmin.to_f, -ymax.to_f, width, height].map { |value| value.round(4) }.join(' ')
        shapes[code] = { path: path, viewbox: viewbox }
      end
    end

    def source_sql(codes)
      quoted = codes.map { |code| ApplicationRecord.connection.quote(code) }.join(', ')

      <<~SQL.squish
        SELECT #{@source[:column]} AS code, geom::geometry AS g0
        FROM #{@source[:table]}
        WHERE #{@source[:column]} IN (#{quoted})
      SQL
    end

    def sql(codes)
      geometry = @level == :country ? country_geometry_sql : 'g0'
      shapes_sql(source_sql(codes), "SELECT code, #{geometry} AS g0 FROM src")
    end

    def collection_sql(key)
      frame = COLLECTION_FRAMES[key]
      geometry = frame ? "ST_CollectionExtract(ST_Intersection(g0, #{envelope_sql(frame)}), 3)" : 'g0'

      # Start from raw boundaries, not independently framed/unwrapped cards:
      # a collection needs one common longitude domain and includes overseas
      # land in world achievements. Pacific collections can unwrap together.
      shapes_sql(source_sql(@codes), <<~SQL.squish)
        SELECT 'collection' AS code, ST_CollectionExtract(ST_Collect(#{geometry}), 3) AS g0 FROM src
      SQL
    end

    def country_geometry_sql
      cases = COUNTRY_FRAMES.map do |code, frame|
        <<~SQL.squish
          WHEN '#{code}' THEN COALESCE(
            (SELECT ST_Collect(part.geom) FROM ST_Dump(g0) AS part
             WHERE ST_Intersects(part.geom, #{envelope_sql(frame)})), g0)
        SQL
      end.join(' ')
      "CASE code #{cases} ELSE g0 END"
    end

    def envelope_sql(frame)
      "ST_MakeEnvelope(#{frame.join(', ')}, 4326)"
    end

    def shapes_sql(source, framed)
      # Tolerance adapts to the geometry's extent so small countries keep a
      # recognizable outline instead of collapsing into a blob.
      # Materialize expensive stages once; inlining duplicates their subqueries.
      # Only unwrap shapes fitting a hemisphere. A world map must not move its
      # seam to Greenwich just because that saves a few degrees of empty space.
      <<~SQL.squish
        WITH src AS (#{source}),
        framed AS MATERIALIZED (#{framed}),
        shifted AS MATERIALIZED (
          SELECT code, g0, ST_ShiftLongitude(g0) AS shifted FROM framed
        ),
        unwrapped AS MATERIALIZED (
          SELECT code,
                 CASE WHEN ST_XMax(g0) - ST_XMin(g0) > 180
                           AND ST_XMax(shifted) - ST_XMin(shifted) < 180
                      THEN shifted ELSE g0 END AS g0
          FROM shifted
        ),
        shapes AS MATERIALIZED (
          SELECT code,
                 ST_SimplifyPreserveTopology(
                   g0,
                   LEAST(#{TOLERANCE},
                         GREATEST(ST_XMax(g0) - ST_XMin(g0), ST_YMax(g0) - ST_YMin(g0)) / 80.0)
                 ) AS g
          FROM unwrapped
        )
        SELECT code, ST_AsSVG(g, 0, 4),
               ST_XMin(g), ST_YMin(g), ST_XMax(g), ST_YMax(g)
        FROM shapes
        WHERE g IS NOT NULL AND NOT ST_IsEmpty(g)
      SQL
    end
  end
end
