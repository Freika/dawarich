# frozen_string_literal: true

class Place < ApplicationRecord
  include Nearable
  include Distanceable

  DEFAULT_NAME = 'Suggested place'

  validates :name, :lonlat, presence: true

  has_many :visits, dependent: :destroy
  has_many :place_visits, dependent: :destroy
  has_many :suggested_visits, -> { distinct }, through: :place_visits, source: :visit

  enum :source, { manual: 0, photon: 1 }

  def lon
    lonlat.x
  end

  def lat
    lonlat.y
  end

  def async_reverse_geocode
    return unless DawarichSettings.reverse_geocoding_enabled?

    ReverseGeocodingJob.perform_later(self.class.to_s, id)
  end

  def reverse_geocoded?
    geodata.present?
  end
end
