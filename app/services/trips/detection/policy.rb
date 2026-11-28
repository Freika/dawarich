# frozen_string_literal: true

module Trips
  module Detection
    # The fixed thresholds of Trip Detection. They are not user settings.
    module Policy
      AWAY_DISTANCE_M = 50_000
      NIGHT_HOUR = 3
      ROAD_JOIN_WINDOW = 24.hours
      MAX_TRIP_DURATION = 90.days
      HOME_RADIUS_FLOOR_M = 500
    end
  end
end
