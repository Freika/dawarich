# frozen_string_literal: true

class Points::NightlyReverseGeocodingJob < ApplicationJob
  queue_as :reverse_geocoding

  def perform
    config = Geocoding::Config.resolved_config
    return unless config.enabled?

    processed_user_ids = Set.new

    Point.not_reverse_geocoded.find_each(batch_size: 1000) do |point|
      point.async_reverse_geocode(force: true, config: config)
      processed_user_ids.add(point.user_id)
    end

    processed_user_ids.each do |user_id|
      Cache::InvalidateUserCaches.new(user_id).call
    end
  end
end
