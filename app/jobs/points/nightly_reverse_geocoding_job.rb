# frozen_string_literal: true

class Points::NightlyReverseGeocodingJob < ApplicationJob
  queue_as :reverse_geocoding

  def perform
    scope = points_scope
    return if scope.nil?

    processed_user_ids = Set.new
    enabled_by_user = Hash.new { |cache, user_id| cache[user_id] = Geocoding::Config.for(user_id).enabled? }

    scope.find_each(batch_size: 1000) do |point|
      next unless enabled_by_user[point.user_id]

      point.async_reverse_geocode(force: true)
      processed_user_ids.add(point.user_id)
    end

    processed_user_ids.each do |user_id|
      Cache::InvalidateUserCaches.new(user_id).call
    end
  end

  private

  def points_scope
    return Point.not_reverse_geocoded if DawarichSettings.reverse_geocoding_enabled?

    enabled_user_ids = ServiceSetting.service_geocoding.where(active: true).pluck(:user_id)
    return if enabled_user_ids.empty?

    Point.not_reverse_geocoded.where(user_id: enabled_user_ids)
  end
end
