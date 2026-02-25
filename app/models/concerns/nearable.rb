# frozen_string_literal: true

module Nearable
  extend ActiveSupport::Concern

  class_methods do
    # It accepts an array of coordinates [latitude, longitude]
    # and an optional radius and distance unit

    def near(*args)
      latitude, longitude, radius, unit = extract_coordinates_and_options(*args)

      unless ::DISTANCE_UNITS.key?(unit.to_sym)
        raise ArgumentError, "Invalid unit. Supported units are: #{::DISTANCE_UNITS.keys.join(', ')}"
      end

      # Convert radius to meters for ST_DWithin
      radius_in_meters = radius * ::DISTANCE_UNITS[unit.to_sym]

      # Create a point from the given coordinates
      point = "SRID=4326;POINT(#{longitude} #{latitude})"

      where(<<-SQL.squish)
        ST_DWithin(
          lonlat::geography,
          ST_GeomFromEWKT('#{point}')::geography,
          #{radius_in_meters}
        )
      SQL
    end

    def with_distance(*args)
      latitude, longitude, unit = extract_coordinates_and_options(*args)

      unless ::DISTANCE_UNITS.key?(unit.to_sym)
        raise ArgumentError, "Invalid unit. Supported units are: #{::DISTANCE_UNITS.keys.join(', ')}"
      end

      point = "SRID=4326;POINT(#{longitude} #{latitude})"
      conversion_factor = 1.0 / ::DISTANCE_UNITS[unit.to_sym]

      select(<<-SQL.squish)
        #{table_name}.*,
        ST_Distance(
          lonlat::geography,
          ST_GeomFromEWKT('#{point}')::geography
        ) * #{conversion_factor} as distance_in_#{unit}
      SQL
    end
    # rubocop:enable Metrics/MethodLength

    private

    def extract_coordinates_and_options(*args)
      coords = args.first
      if !coords.is_a?(Array) || coords.length != 2
        raise ArgumentError,
              'First argument must be coordinates array containing exactly 2 elements [latitude, longitude]'
      end

      [coords[0], coords[1], *args[1..]].tap do |extracted|
        # Set default values for missing options
        extracted[2] ||= 1 if extracted.length < 3 # default radius
        extracted[3] ||= :km if extracted.length < 4 # default unit
      end
    end
  end
end
