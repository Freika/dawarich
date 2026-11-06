# frozen_string_literal: true

module Timezones
  # Resolves coordinates to IANA time zone names in one query.
  # Takes { key => [longitude, latitude] } and returns { key => tzid } for
  # the keys it could resolve; with no boundaries loaded it returns {}.
  class Lookup
    SQL = <<~SQL.squish
      SELECT input.ord, zone.tzid
      FROM unnest(ARRAY[?]::float8[], ARRAY[?]::float8[]) WITH ORDINALITY AS input(lon, lat, ord)
      CROSS JOIN LATERAL (
        SELECT timezones.tzid FROM timezones
        WHERE ST_Covers(timezones.geom, ST_SetSRID(ST_MakePoint(input.lon, input.lat), 4326))
        ORDER BY timezones.tzid
        LIMIT 1
      ) AS zone
    SQL

    def self.call(coordinates)
      coordinates = coordinates.compact
      return {} if coordinates.empty?

      keys = coordinates.keys
      sql = Timezone.sanitize_sql_array([SQL, coordinates.values.map { |lon, _| lon.to_f },
                                         coordinates.values.map { |_, lat| lat.to_f }])

      Timezone.connection.select_rows(sql).each_with_object({}) do |(ord, tzid), result|
        result[keys[ord.to_i - 1]] = tzid if ActiveSupport::TimeZone[tzid]
      end
    end
  end
end
