# frozen_string_literal: true

module Tracks
  module RealtimeGeocodeFollowUp
    WINDOW = 5.minutes

    module_function

    def call(user, since: WINDOW.ago)
      config = Geocoding::Config.for(user.id)
      return unless config.enabled?

      user.points.not_reverse_geocoded.where('created_at > ?', since)
          .find_each { |point| point.async_reverse_geocode(config: config) }
    end
  end
end
