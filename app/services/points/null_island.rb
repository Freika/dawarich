# frozen_string_literal: true

module Points::NullIsland
  LONLAT_REGEX = /\APOINT\s*\(\s*-?0(?:\.0+)?\s+-?0(?:\.0+)?\s*\)\z/i

  def self.sql_predicate(column = 'lonlat')
    "(ST_X(#{column}::geometry) = 0 AND ST_Y(#{column}::geometry) = 0)"
  end

  def self.coordinates?(lon, lat)
    lon.to_f.zero? && lat.to_f.zero?
  end

  def self.lonlat?(value)
    value.to_s.match?(LONLAT_REGEX)
  end
end
