# frozen_string_literal: true

module Tracks
  module RealtimeGeocodeFollowUp
    WINDOW = 5.minutes

    module_function

    def call(user, since: WINDOW.ago)
      config = Geocoding::Config.for(user.id)
      return unless config.enabled?

      user.points.not_reverse_geocoded.where('created_at > ?', since).in_batches(of: 1000) do |batch|
        Geocoding::ReverseCommands.enqueue_points(user.id, batch.pluck(:id), force: false,
                                                  producer: 'Tracks::RealtimeGeocodeFollowUp')
      end
    end
  end
end
