# frozen_string_literal: true

class Points::NightlyReverseGeocodingJob < ApplicationJob
  queue_as :reverse_geocoding

  def perform
    config = Geocoding::Config.resolved_config
    return unless config.enabled?

    processed_user_ids = Set.new

    Point.not_reverse_geocoded.in_batches(of: 1000) do |batch|
      batch.pluck(:user_id, :id).group_by(&:first).each do |user_id, rows|
        Geocoding::ReverseCommands.enqueue_points(user_id, rows.map(&:last), force: true,
                                                  producer: 'Points::NightlyReverseGeocodingJob')
        processed_user_ids.add(user_id)
      end
    end

    processed_user_ids.each do |user_id|
      Cache::InvalidateUserCaches.new(user_id).call
    end
  end
end
