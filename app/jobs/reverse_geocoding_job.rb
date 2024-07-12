# frozen_string_literal: true

class ReverseGeocodingJob < ApplicationJob
  queue_as :reverse_geocoding

  def perform(point_id)
    return unless REVERSE_GEOCODING_ENABLED

    ReverseGeocoding::FetchData.new(point_id).call
  end
end
