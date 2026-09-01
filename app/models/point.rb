# frozen_string_literal: true

class Point < ApplicationRecord
  include Nearable
  include Distanceable
  include Archivable
  include PointDimensionReads

  self.ignored_columns += %w[latitude longitude]

  # Every ingest path upserts points and then counts the rows whose `xmax` is
  # zero to tell inserts from updates. `xmax` is Postgres' `xid`, an OID the
  # adapter has no type for, so returning it raw makes the adapter warn the
  # first time each connection sees it. Casting to text keeps `to_i` working
  # and the log quiet.
  UPSERT_RETURNING_COLUMNS =
    'id, xmax::text AS xmax, timestamp, ' \
    'ST_X(lonlat::geometry) AS longitude, ST_Y(lonlat::geometry) AS latitude'

  belongs_to :import, optional: true, counter_cache: true
  belongs_to :visit, optional: true
  belongs_to :user
  belongs_to :country, optional: true
  belongs_to :track, optional: true

  validates :timestamp, :lonlat, presence: true
  validates :lonlat, uniqueness: {
    scope: %i[timestamp user_id],
    message: ->(*) { I18n.t('models.point.already_has_a_point_at_this_location_and_time_for') },
    index: true
  }

  # battery_status/trigger/connection live on point_sources since Release D
  # dropped the legacy columns; PointSource declares the enums (identical
  # mappings) and PointDimensionReads serves the labels through :source.

  scope :reverse_geocoded, -> { where.not(reverse_geocoded_at: nil) }
  scope :not_reverse_geocoded, -> { where(reverse_geocoded_at: nil) }
  scope :visited, -> { where.not(visit_id: nil) }
  scope :not_visited, -> { where(visit_id: nil) }
  scope :complete, -> { where.not(timestamp: nil).where.not(lonlat: nil) }
  scope :not_anomaly, -> { where(anomaly: [false, nil]) }
  scope :anomaly, -> { where(anomaly: true) }
  # Ingest, cleanup and the anomaly filter must all agree on what counts as a
  # broken coordinate; Points::NullIsland owns that definition.
  scope :null_island, -> { where(Points::NullIsland.sql_predicate) }

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

  # Build a key whose equivalence classes match the PostgreSQL UNIQUE index
  # on (user_id, timestamp, lonlat). The raw lonlat WKT string from
  # Points::Params / Overland::Params can differ character-by-character for
  # points that collapse to the same geography(Point, 4326) double, so a
  # plain string `uniq` keeps both variants and the subsequent
  # `Point.upsert_all` fails with `PG::CardinalityViolation: ON CONFLICT DO
  # UPDATE command cannot affect row a second time` — losing the entire
  # 1000-point slice. Parsing to Float matches PG's IEEE 754 normalization.
  def self.dedup_key(attrs)
    raw = attrs[:lonlat].to_s
    inside = raw[/POINT[^(]*\(([^)]*)\)/i, 1] || raw
    lon, lat = inside.scan(/-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?/).map(&:to_f)
    [lon, lat, attrs[:timestamp].to_i, attrs[:user_id]]
  end

  def recorded_at
    @recorded_at ||= Time.zone.at(timestamp)
  end

  GEOCODE_DEDUP_TTL = 1.day.to_i

  def self.geocode_dedup_key(id)
    "geocode:enq:Point:#{id}"
  end

  def async_reverse_geocode(force: false, config: nil)
    config ||= Geocoding::Config.for(user_id)
    return unless config.enabled?

    if force
      Sidekiq.redis { |r| r.del(self.class.geocode_dedup_key(id)) }
    else
      claimed = Sidekiq.redis do |r|
        r.set(self.class.geocode_dedup_key(id), 1, nx: true, ex: GEOCODE_DEDUP_TTL)
      end
      return unless claimed
    end

    begin
      ReverseGeocodingJob.perform_later(self.class.to_s, id, force: force)
    rescue StandardError
      Sidekiq.redis { |r| r.del(self.class.geocode_dedup_key(id)) } unless force
      raise
    end
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

  # The physical column was dropped in Release D; the name stays as the
  # serializer contract (the scratch map reads properties.country_name).
  def country_name
    country&.name || ''
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

  # family_sharing_enabled? goes first: it answers from already-loaded data,
  # while the plan check loads the family and its owner on cloud.
  def should_broadcast_to_family?
    return false unless user.family_sharing_enabled?

    DawarichSettings.family_feature_available_for?(user)
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
