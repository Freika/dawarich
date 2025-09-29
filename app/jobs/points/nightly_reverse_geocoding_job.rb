# frozen_string_literal: true

class Points::NightlyReverseGeocodingJob < ApplicationJob
  queue_as :reverse_geocoding

  def perform
    return unless DawarichSettings.reverse_geocoding_enabled?

    Point.not_reverse_geocoded.find_each(batch_size: 1000) do |point|
      point.async_reverse_geocode
    end
  end
end
