# frozen_string_literal: true

module Stats
  class YearRoutesQuery
    # A year's routes are drawn on a small preview, so detail finer than about
    # 1/400 of the year's extent is invisible there and only bloats the page.
    SIMPLIFY_FRACTION = 400.0
    TOLERANCE_STEPS = [1, 4, 16].freeze
    MAX_COORDINATES = 4_000
    PRECISION = 4

    def initialize(user, year)
      @user = user
      @year = year
    end

    def call
      lines = []
      TOLERANCE_STEPS.each do |step|
        lines = simplified_lines(step)
        break if lines.sum(&:size) <= MAX_COORDINATES
      end

      within_cap(lines).presence
    end

    def any?
      year_tracks.exists?
    end

    def cache_key
      latest, count = year_tracks.pick(Arel.sql('MAX(tracks.updated_at), COUNT(*)'))
      ['year_routes', user.id, year, user.timezone_iana, latest&.iso8601(6), count]
    end

    private

    attr_reader :user, :year

    def simplified_lines(step)
      collected = year_tracks.select('ST_Collect(tracks.original_path) AS geom')
      geojson = Track.from(collected, :year_tracks).pick(Arel.sql(<<~SQL.squish))
        ST_AsGeoJSON(
          ST_Simplify(
            year_tracks.geom,
            GREATEST(
              ST_XMax(year_tracks.geom) - ST_XMin(year_tracks.geom),
              ST_YMax(year_tracks.geom) - ST_YMin(year_tracks.geom)
            ) * #{step.to_i} / #{SIMPLIFY_FRACTION}
          ),
          #{PRECISION}
        )
      SQL
      geojson.present? ? lines(JSON.parse(geojson)) : []
    end

    def within_cap(lines)
      return lines if lines.sum(&:size) <= MAX_COORDINATES

      budget = MAX_COORDINATES
      lines.sort_by { -_1.size }.each_with_object([]) do |line, kept|
        next if line.size > budget

        kept << line
        budget -= line.size
      end
    end

    def year_tracks
      zone = ActiveSupport::TimeZone[user.timezone_iana] || Time.zone
      user.scoped_tracks.where(start_at: zone.local(year, 1, 1)...zone.local(year + 1, 1, 1))
    end

    def lines(geometry)
      case geometry['type']
      when 'LineString' then [geometry['coordinates']]
      when 'MultiLineString' then geometry['coordinates']
      when 'GeometryCollection' then geometry['geometries'].flat_map { lines(_1) }
      else []
      end.select { _1.size > 1 }
    end
  end
end
