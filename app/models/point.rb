# frozen_string_literal: true

class Point < ApplicationRecord
  include Nearable
  include Distanceable

  belongs_to :import, optional: true, counter_cache: true
  belongs_to :visit, optional: true
  belongs_to :user
  belongs_to :country, optional: true
  belongs_to :track, optional: true

  validates :timestamp, :lonlat, presence: true
  validates :lonlat, uniqueness: {
    scope: %i[timestamp user_id],
    message: 'already has a point at this location and time for this user',
    index: true
  }

  enum :battery_status, { unknown: 0, unplugged: 1, charging: 2, full: 3 }, suffix: true
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
  after_create_commit :trigger_track_processing, if: -> { import_id.nil? }
  after_commit :recalculate_track, on: :update

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

  private

  # rubocop:disable Metrics/MethodLength Metrics/AbcSize
  def broadcast_coordinates
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

  def country_name
    # We have a country column in the database,
    # but we also have a country_id column.
    # TODO: rename country column to country_name
    self.country&.name || read_attribute(:country) || ''
  end

  def recalculate_track
    return unless track.present?

    track.recalculate_path_and_distance!
  end

  def trigger_track_processing
    # Smart track processing: immediate for track boundaries, batched for continuous tracking
    previous_point = user.points.where('timestamp < ?', timestamp)
                                .order(timestamp: :desc)
                                .first
    
    if should_trigger_immediate_processing?(previous_point)
      # Process immediately for obvious track boundaries
      TrackProcessingJob.perform_now(user_id, 'incremental', point_id: id)
    else
      # Batch processing for continuous tracking (reduces job queue load)
      TrackProcessingJob.perform_later(user_id, 'incremental', point_id: id)
    end
  end
  
  def should_trigger_immediate_processing?(previous_point)
    return true if previous_point.nil?
    
    # Immediate processing for obvious track boundaries
    time_diff = timestamp - previous_point.timestamp
    return true if time_diff > 30.minutes # Long gap = likely new track
    
    # Calculate distance for large jumps
    distance_km = Geocoder::Calculations.distance_between(
      [previous_point.lat, previous_point.lon],
      [lat, lon],
      units: :km
    )
    return true if distance_km > 1.0 # Large jump = likely new track
    
    false
  end
end
