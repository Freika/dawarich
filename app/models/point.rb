# frozen_string_literal: true

class Point < ApplicationRecord
  include Nearable
  include Distanceable

  belongs_to :import, optional: true, counter_cache: true
  belongs_to :visit, optional: true
  belongs_to :user, counter_cache: true
  belongs_to :country, optional: true
  belongs_to :track, optional: true

  validates :timestamp, :lonlat, presence: true
  validates :lonlat, uniqueness: {
    scope: %i[timestamp user_id],
    message: 'already has a point at this location and time for this user',
    index: true
  }

  enum :battery_status, { unknown: 0, unplugged: 1, charging: 2, full: 3, connected_not_charging: 4, discharging: 5 }, suffix: true
  enum :trigger, {
    unknown: 0, background_event: 1, circular_region_event: 2, beacon_event: 3,
    report_location_message_event: 4, manual_event: 5, timer_based_event: 6,
    settings_monitoring_event: 7
  }, suffix: true
  enum :connection, { mobile: 0, wifi: 1, offline: 2, unknown: 4 }, suffix: true

  scope :reverse_geocoded, -> { where.not(reverse_geocoded_at: nil) }
  scope :not_reverse_geocoded, -> { where(reverse_geocoded_at: nil) }
  scope :visited, -> { where.not(visit_id: nil) }
  scope :not_visited, -> { where(visit_id: nil) }

  after_create :async_reverse_geocode, if: -> { DawarichSettings.store_geodata? && !reverse_geocoded? }
  after_create :set_country
  after_create_commit :broadcast_coordinates
  # after_create_commit :trigger_incremental_track_generation, if: -> { import_id.nil? }
  # after_commit :recalculate_track, on: :update, if: -> { track.present? }

  def self.without_raw_data
    select(column_names - ['raw_data'])
  end

  def recorded_at
    @recorded_at ||= Time.zone.at(timestamp)
  end

  def async_reverse_geocode
    return unless DawarichSettings.reverse_geocoding_enabled?

    ReverseGeocodingJob.perform_later(self.class.to_s, id)
  end

  def reverse_geocoded?
    reverse_geocoded_at.present?
  end

  def lon
    lonlat.x
  end

  def lat
    lonlat.y
  end

  def found_in_country
    Country.containing_point(lon, lat)
  end

  def country_name
    # TODO: Remove the country column in the future.
    read_attribute(:country_name) || self.country&.name || read_attribute(:country) || ''
  end

  private

  # rubocop:disable Metrics/MethodLength Metrics/AbcSize
  def broadcast_coordinates
    return unless user.safe_settings.live_map_enabled

    PointsChannel.broadcast_to(
      user,
      [
        lat,
        lon,
        battery.to_s,
        altitude.to_s,
        timestamp.to_s,
        velocity.to_s,
        id.to_s,
        country_name.to_s
      ]
    )
  end
  # rubocop:enable Metrics/MethodLength

  def set_country
    self.country_id = found_in_country&.id
    save! if changed?
  end

  def recalculate_track
    track.recalculate_path_and_distance!
  end

  def trigger_incremental_track_generation
    Tracks::IncrementalCheckJob.perform_later(user.id, id)
  end
end
