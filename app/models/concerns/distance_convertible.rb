# frozen_string_literal: true

# Module for converting distances from stored meters to user's preferred unit at runtime.
#
# All distances are stored in meters in the database for consistency. This module provides
# methods to convert those stored meter values to the user's preferred unit (km, mi, etc.)
# for display purposes.
#
# This approach ensures:
# - Consistent data storage regardless of user preferences
# - No data corruption when users change distance units
# - Easy conversion for display without affecting stored data
#
# Usage:
#   class Track < ApplicationRecord
#     include DistanceConvertible
#   end
#
#   track.distance                    # => 5000 (meters stored in DB)
#   track.distance_in_unit('km')      # => 5.0 (converted to km)
#   track.distance_in_unit('mi')      # => 3.11 (converted to miles)
#
module DistanceConvertible
  extend ActiveSupport::Concern

  def distance_in_unit(unit)
    return 0.0 unless distance.present?

    unit_sym = unit.to_sym
    conversion_factor = ::DISTANCE_UNITS[unit_sym]

    unless conversion_factor
      raise ArgumentError, "Invalid unit '#{unit}'. Supported units: #{::DISTANCE_UNITS.keys.join(', ')}"
    end

    # Distance is stored in meters, convert to target unit
    distance.to_f / conversion_factor
  end

  module ClassMethods
    def convert_distance(distance_meters, unit)
      return 0.0 unless distance_meters.present?

      unit_sym = unit.to_sym
      conversion_factor = ::DISTANCE_UNITS[unit_sym]

      unless conversion_factor
        raise ArgumentError, "Invalid unit '#{unit}'. Supported units: #{::DISTANCE_UNITS.keys.join(', ')}"
      end

      distance_meters.to_f / conversion_factor
    end
  end
end
