# frozen_string_literal: true

module Achievements
  # Builds SVG outlines for locked cards from the stored geometries, so an
  # unearned region shows its shape (scratch-map style) instead of a bare lock.
  class RegionSilhouettes
    TOLERANCE = 0.02

    CACHE_VERSION = 1
    CACHE_TTL = 1.week

    SOURCES = {
      subdivision: { table: 'regions', column: 'code' },
      country: { table: 'countries', column: 'iso_a2' }
    }.freeze

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
      rows(codes).each_with_object({}) do |(code, path, xmin, ymin, xmax, ymax), shapes|
        width = xmax.to_f - xmin.to_f
        height = ymax.to_f - ymin.to_f
        next if path.blank? || width.zero? || height.zero?

        # ST_AsSVG emits Y negated (SVG's axis points down), so the viewBox
        # starts at -ymax rather than ymin.
        viewbox = [xmin.to_f, -ymax.to_f, width, height].map { |value| value.round(4) }.join(' ')
        shapes[code] = { path: path, viewbox: viewbox }
      end
    end

    def rows(codes)
      ApplicationRecord.connection.select_rows(sql(codes))
    end

    def sql(codes)
      quoted = codes.map { |code| ApplicationRecord.connection.quote(code) }.join(', ')

      # Tolerance adapts to the geometry's extent so small countries keep a
      # recognizable outline instead of collapsing into a blob.
      <<~SQL.squish
        WITH src AS (
          SELECT #{@source[:column]} AS code, geom::geometry AS g0
          FROM #{@source[:table]}
          WHERE #{@source[:column]} IN (#{quoted})
        ),
        shapes AS (
          SELECT code,
                 ST_SimplifyPreserveTopology(
                   g0,
                   LEAST(#{TOLERANCE},
                         GREATEST(ST_XMax(g0) - ST_XMin(g0), ST_YMax(g0) - ST_YMin(g0)) / 80.0)
                 ) AS g
          FROM src
        )
        SELECT code, ST_AsSVG(g, 0, 4),
               ST_XMin(g), ST_YMin(g), ST_XMax(g), ST_YMax(g)
        FROM shapes
        WHERE g IS NOT NULL AND NOT ST_IsEmpty(g)
      SQL
    end
  end
end
