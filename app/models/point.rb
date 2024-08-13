# frozen_string_literal: true

class Point < ApplicationRecord
  reverse_geocoded_by :latitude, :longitude

  belongs_to :import, optional: true
  belongs_to :visit, optional: true
  belongs_to :user

  validates :latitude, :longitude, :timestamp, presence: true

  enum battery_status: { unknown: 0, unplugged: 1, charging: 2, full: 3 }, _suffix: true
  enum trigger: {
    unknown: 0, background_event: 1, circular_region_event: 2, beacon_event: 3,
    report_location_message_event: 4, manual_event: 5, timer_based_event: 6,
    settings_monitoring_event: 7
  }, _suffix: true
  enum connection: { mobile: 0, wifi: 1, offline: 2 }, _suffix: true

  scope :reverse_geocoded, -> { where.not(city: nil, country: nil) }
  scope :not_reverse_geocoded, -> { where(city: nil, country: nil) }
  scope :visited, -> { where.not(visit_id: nil) }
  scope :not_visited, -> { where(visit_id: nil) }

  after_create :async_reverse_geocode

  def self.without_raw_data
    select(column_names - ['raw_data'])
  end

  def recorded_at
    Time.zone.at(timestamp)
  end

  def async_reverse_geocode
    return unless REVERSE_GEOCODING_ENABLED

    ReverseGeocodingJob.perform_later(self.class.to_s, id)
  end
end
