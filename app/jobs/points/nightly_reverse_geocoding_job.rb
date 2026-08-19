# frozen_string_literal: true

class Points::NightlyReverseGeocodingJob < ApplicationJob
  queue_as :reverse_geocoding

  def perform
    return unless DawarichSettings.reverse_geocoding_enabled? ||
                  ServiceSetting.service_geocoding.where(active: true).exists?

    processed_user_ids = Set.new
    enabled_by_user = Hash.new { |cache, user_id| cache[user_id] = Geocoding::Config.for(user_id).enabled? }

    Point.not_reverse_geocoded.find_each(batch_size: 1000) do |point|
      next unless enabled_by_user[point.user_id]

      point.async_reverse_geocode(force: true)
      processed_user_ids.add(point.user_id)
    end

    processed_user_ids.each do |user_id|
      Cache::InvalidateUserCaches.new(user_id).call
    end
  end
end
