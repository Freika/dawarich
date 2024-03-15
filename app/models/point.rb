class Point < ApplicationRecord
  belongs_to :import, optional: true

  validates :latitude, :longitude, :tracker_id, :timestamp, :topic, presence: true

  enum battery_status: { unknown: 0, unplugged: 1, charging: 2, full: 3 }, _suffix: true
  enum trigger: {
    unknown: 0, background_event: 1, circular_region_event: 2, beacon_event: 3,
    report_location_message_event: 4, manual_event: 5, timer_based_event: 6,
    settings_monitoring_event: 7
  }, _suffix: true
  enum connection: { mobile: 0, wifi: 1, offline: 2 }, _suffix: true

  after_create :async_reverse_geocode

  def tracked_at
    Time.at(timestamp).strftime('%Y-%m-%d %H:%M:%S')
  end

  def cities_by_countries
    group_by { _1.country }.compact.map { |k, v| { k => v.pluck(:city).uniq.compact } }
  end

  private

  def async_reverse_geocode
    ReverseGeocodingJob.perform_later(id)
  end
end


def group_records_by_hour(records)
  grouped_records = Hash.new { |hash, key| hash[key] = [] }

  records.each do |record|
    # Round timestamp to the nearest hour
    rounded_time = Time.at(record.timestamp).beginning_of_hour
    grouped_records[rounded_time] << record
  end

  grouped_records
end
