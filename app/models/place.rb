# frozen_string_literal: true

class Place < ApplicationRecord
  DEFAULT_NAME = 'Suggested place'
  reverse_geocoded_by :latitude, :longitude

  validates :name, :longitude, :latitude, presence: true

  has_many :visits, dependent: :destroy
  has_many :place_visits, dependent: :destroy
  has_many :suggested_visits, through: :place_visits, source: :visit

  enum :source, { manual: 0, photon: 1 }

  def async_reverse_geocode
    return unless REVERSE_GEOCODING_ENABLED

    ReverseGeocodingJob.perform_later(self.class.to_s, id)
  end

  def reverse_geocoded?
    geodata.present?
  end
end
