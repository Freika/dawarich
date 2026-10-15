# frozen_string_literal: true

module Stats
  class YearRoutesQuery
    # A year's routes are drawn on a small preview, so detail finer than about
    # 1/400 of the year's extent is invisible there and only bloats the page.
    SIMPLIFY_FRACTION = 400.0
    PRECISION = 4

    def initialize(user, year)
      @user = user
      @year = year
    end

    def call
      geojson = Track.from(collected_tracks, :year_tracks).pick(Arel.sql(<<~SQL.squish))
        ST_AsGeoJSON(
          ST_Simplify(
            year_tracks.geom,
            GREATEST(
              ST_XMax(year_tracks.geom) - ST_XMin(year_tracks.geom),
              ST_YMax(year_tracks.geom) - ST_YMin(year_tracks.geom)
            ) / #{SIMPLIFY_FRACTION}
          ),
          #{PRECISION}
        )
      SQL
      return if geojson.blank?

      lines(JSON.parse(geojson)).presence
    end

    private

    attr_reader :user, :year

    def collected_tracks
      zone = ActiveSupport::TimeZone[user.timezone_iana] || Time.zone
      period = zone.local(year, 1, 1)...zone.local(year + 1, 1, 1)

      user.scoped_tracks.where(start_at: period).select('ST_Collect(tracks.original_path) AS geom')
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
