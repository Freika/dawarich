# frozen_string_literal: true

class Place < ApplicationRecord
  validates :name, :longitude, :latitude, presence: true

  enum source: { manual: 0, google_places: 1 }

  after_commit :async_reverse_geocode, on: :create

  private

  def async_reverse_geocode
    return unless REVERSE_GEOCODING_ENABLED

    ReverseGeocodingJob.perform_later(self.class.to_s, id)
  end
end
