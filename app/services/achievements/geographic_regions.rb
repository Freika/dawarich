# frozen_string_literal: true

module Achievements
  class GeographicRegions
    RADIUS = 6_371_008.8
    MARGIN = 10_000.0
    POLAR_LATITUDE = 66.56
    GROUPS = {
      'north_south' => %w[north south],
      'east_west' => %w[east west],
      'four_quarters' => %w[ne nw se sw],
      'arctic' => ['arctic'],
      'antarctic' => ['antarctic']
    }.freeze

    def self.memberships(lat, lon)
      latitude = lat * Math::PI / 180
      longitude = lon * Math::PI / 180
      north_south = if latitude.abs * RADIUS >= MARGIN
                      lat.positive? ? 'north' : 'south'
                    end
      # Distance to the meridian great circle also excludes the opposite
      # meridian, so dateline jitter cannot satisfy both east and west.
      meridian_distance = Math.asin((Math.cos(latitude) * Math.sin(longitude)).abs.clamp(0, 1)) * RADIUS
      east_west = (lon.positive? ? 'east' : 'west') if meridian_distance >= MARGIN
      keys = [north_south, east_west].compact
      keys << "#{north_south.first}#{east_west.first}" if north_south && east_west
      polar_margin = MARGIN * 180 / (Math::PI * RADIUS)
      keys << 'arctic' if lat >= POLAR_LATITUDE + polar_margin
      keys << 'antarctic' if lat <= -POLAR_LATITUDE - polar_margin
      keys
    end
  end
end
