# frozen_string_literal: true

class Point < ApplicationRecord
  include Nearable
  include Distanceable
  include Archivable

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

  enum :battery_status, { unknown: 0, unplugged: 1, charging: 2, full: 3, connected_not_charging: 4, discharging: 5 },
       suffix: true
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
  scope :not_anomaly, -> { where(anomaly: [false, nil]) }
  scope :anomaly, -> { where(anomaly: true) }

  after_create :async_reverse_geocode, if: -> { DawarichSettings.store_geodata? && !reverse_geocoded? }
  after_create :set_country
  after_create_commit :broadcast_coordinates
  # after_commit :recalculate_track, on: :update, if: -> { track.present? }

  def self.without_raw_data
    select(column_names - ['raw_data'])
  end

  # Memoized at class-load to avoid `Point.column_names.include?` lookups on
  # every row during bulk imports (importer params files call this thousands
  # of times per batch). The constant evaluates once per process; if the
  # schema changes mid-process (e.g. dev migration), restart Rails.
  ALTITUDE_DECIMAL_SUPPORTED = column_names.include?('altitude_decimal')

  def self.altitude_decimal_supported?
    ALTITUDE_DECIMAL_SUPPORTED
  end

  def recorded_at
    @recorded_at ||= Time.zone.at(timestamp)
  end

  def async_reverse_geocode(force: false)
    return unless DawarichSettings.reverse_geocoding_enabled?

    ReverseGeocodingJob.perform_later(self.class.to_s, id, force: force)
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
    read_attribute(:country_name) || country&.name || self[:country] || ''
  end

  # Stage 1 of the altitude integer→decimal migration: prefer the new
  # `altitude_decimal` column when it carries a value, fall back to the
  # legacy integer `altitude` column otherwise. Writes always update the
  # decimal column so new data is full-precision; the integer column gets
  # the truncated value via the underlying attribute.
  #
  # `has_attribute?` guards against MissingAttributeError when the record
  # was loaded with a partial `.select(...)` that omitted altitude_decimal
  # (e.g. the altitude backfill job uses `.select(:id, :altitude, :raw_data)`
  # for streaming-friendly memory usage).
  def altitude
    if has_attribute?(:altitude_decimal)
      decimal = self[:altitude_decimal]
      return decimal if decimal.present?
    end

    self[:altitude] if has_attribute?(:altitude)
  end

  def altitude=(value)
    self[:altitude] = value if has_attribute?(:altitude)
    self[:altitude_decimal] = value if has_attribute?(:altitude_decimal)
  end

  private

  # Metrics/AbcSize
  def broadcast_coordinates
    if user.safe_settings.live_map_enabled
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

    broadcast_to_family if should_broadcast_to_family?
  end

  def should_broadcast_to_family?
    return false unless DawarichSettings.family_feature_enabled?
    return false unless user.in_family?
    return false unless user.family_sharing_enabled?

    true
  end

  def broadcast_to_family
    FamilyLocationsChannel.broadcast_to(
      user.family,
      {
        user_id: user.id,
        email: user.email,
        email_initial: user.email.first.upcase,
        latitude: lat,
        longitude: lon,
        timestamp: timestamp.to_i,
        updated_at: Time.zone.at(timestamp.to_i).iso8601
      }
    )
  end

  def set_country
    self.country_id = found_in_country&.id
    save! if changed?
  end

  def recalculate_track
    track.recalculate_path_and_distance!
  end
end
