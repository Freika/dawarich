# frozen_string_literal: true

module Points::NullIsland
  # Exact (0, 0) is the classic sentinel, but Google Timeline and some trackers
  # emit coordinates a fraction of a degree off zero instead — the same broken
  # reading, and an equality check silently lets those through. The
  # neighbourhood is open ocean roughly 570km off West Africa, so nothing
  # legitimate lands inside it.
  RADIUS_METERS = 5_000
  LONLAT_REGEX = /\APOINT\s*\(\s*(-?\d+(?:\.\d+)?)\s+(-?\d+(?:\.\d+)?)\s*\)\z/i

  def self.sql_predicate(column = 'lonlat')
    "ST_DWithin(#{column}::geography, ST_SetSRID(ST_MakePoint(0, 0), 4326)::geography, #{RADIUS_METERS})"
  end

  def self.coordinates?(lon, lat)
    kilometers = Geocoder::Calculations.distance_between(
      [lat.to_f, lon.to_f], [0.0, 0.0], units: :km
    )

    kilometers * 1_000 <= RADIUS_METERS
  end

  def self.lonlat?(value)
    match = LONLAT_REGEX.match(value.to_s)
    return false if match.nil?

    coordinates?(match[1], match[2])
  end
end
