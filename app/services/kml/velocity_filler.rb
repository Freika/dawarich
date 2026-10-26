# frozen_string_literal: true

module Kml
  module VelocityFiller
    MAX_LEG_SPEED_MS = 1200 / 3.6

    module_function

    def call(points_data)
      ordered = points_data.sort_by.with_index { |point, index| [point[:timestamp], index] }
      leg_speeds = ordered.each_cons(2).map { |previous, current| leg_speed(previous, current) }

      ordered.each_with_index do |point, index|
        next unless point[:velocity].nil?

        legs = [index.positive? ? leg_speeds[index - 1] : nil, leg_speeds[index]]
        point[:velocity] = legs.all? ? legs.min.round(1) : 0.0
      end
      points_data
    end

    def leg_speed(previous, current)
      elapsed = current[:timestamp] - previous[:timestamp]
      return unless elapsed.positive?

      speed = Geocoder::Calculations.distance_between(lat_lng(previous), lat_lng(current), units: :km) * 1000 / elapsed
      speed if speed <= MAX_LEG_SPEED_MS
    end

    def lat_lng(point)
      point[:lonlat].delete_prefix('POINT(').delete_suffix(')').split.map(&:to_f).reverse
    end
  end
end
