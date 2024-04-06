class Point < ApplicationRecord
  belongs_to :import, optional: true

  validates :latitude, :longitude, :timestamp, presence: true

  enum battery_status: { unknown: 0, unplugged: 1, charging: 2, full: 3 }, _suffix: true
  enum trigger: {
    unknown: 0, background_event: 1, circular_region_event: 2, beacon_event: 3,
    report_location_message_event: 4, manual_event: 5, timer_based_event: 6,
    settings_monitoring_event: 7
  }, _suffix: true
  enum connection: { mobile: 0, wifi: 1, offline: 2 }, _suffix: true

  after_create :async_reverse_geocode

  private

  def async_reverse_geocode
    return unless REVERSE_GEOCODING_ENABLED

    ReverseGeocodingJob.perform_later(id)
  end
end
