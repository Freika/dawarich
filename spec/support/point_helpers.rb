# frozen_string_literal: true

module PointHelpers
  # Creates a list of points spaced ~100m apart northwards
  def create_points_around(user:, count:, base_lat: 20.0, base_lon: 10.0, timestamp: nil, **attrs)
    Array.new(count) do |i|
      create(
        :point,
        user: user,
        timestamp: (timestamp.respond_to?(:call) ? timestamp.call(i) : timestamp) || (Time.current - i.minutes).to_i,
        lonlat: "POINT(#{base_lon} #{base_lat + i * 0.0009})",
        **attrs
      )
    end
  end
end

RSpec.configure do |config|
  config.include PointHelpers
end
