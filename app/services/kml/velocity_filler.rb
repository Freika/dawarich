# frozen_string_literal: true

module Kml
  module VelocityFiller
    module_function

    def call(points_data)
      ordered = points_data.sort_by.with_index { |point, index| [point[:timestamp], index] }
      leg_speeds = ordered.each_cons(2).map { |previous, current| leg_speed(previous, current) }

      ordered.each_with_index do |point, index|
        next unless point[:velocity].zero? && index.positive?

        legs = [leg_speeds[index - 1], leg_speeds[index]]
        point[:velocity] = legs.min.round(1) if legs.all?
      end
      points_data
    end

    def leg_speed(previous, current)
      elapsed = current[:timestamp] - previous[:timestamp]
      return unless elapsed.positive?

      Geocoder::Calculations.distance_between(lat_lng(previous), lat_lng(current), units: :km) * 1000 / elapsed
    end

    def lat_lng(point)
      point[:lonlat].delete_prefix('POINT(').delete_suffix(')').split.map(&:to_f).reverse
    end
  end
end
