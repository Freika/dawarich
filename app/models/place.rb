# frozen_string_literal: true

class Place < ApplicationRecord
  include Demoable
  include Nearable
  include Distanceable
  include Taggable
  include Notable
  include Geofenceable

  DEFAULT_NAME = 'Suggested place'
  MAX_VISIT_RADIUS = 50_000

  belongs_to :user
  has_many :visits, dependent: :nullify
  # Reader surfaces (drawers, serializers, stats) must never count tombstoned
  # or declined visits; eager-loadable so list endpoints avoid N+1 counts.
  # dependent: nil — lifecycle belongs to the canonical :visits association.
  has_many :active_visits, -> { active }, class_name: 'Visit', inverse_of: :place, dependent: nil
  has_many :place_visits, dependent: :destroy
  has_many :suggested_visits, -> { distinct }, through: :place_visits, source: :visit
  has_many :legacy_area_place_mappings, dependent: :delete_all
  has_many :achievement_selections, class_name: 'Achievements::Selection', dependent: :destroy
  has_many :homes, dependent: :destroy

  attr_accessor :machine_named, :user_named, :skip_suggested_visit_reattribution,
                :reattribute_suggested_visits_on_create

  before_validation :build_lonlat, if: -> { latitude.present? && longitude.present? }
  before_save :lock_name_on_user_edit
  after_commit :schedule_suggested_visit_reattribution,
               on: %i[create update],
               if: :suggested_visit_reattribution_needed?
  after_update -> { carry_name_to_visits(name_before_last_save) }, if: :saved_change_to_name?
  after_commit -> { Trips::DetectJob.schedule(user_id) },
               on: :update, if: -> { saved_change_to_lonlat? && homes.exists? }

  validates :name, presence: true, length: { maximum: 255 }
  validates :lonlat, presence: true
  validates :visit_radius,
            numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: MAX_VISIT_RADIUS }

  enum :source, { manual: 0, photon: 1, gpx_waypoint: 2 }

  scope :archived, -> { where.not(archived_at: nil) }
  scope :not_archived, -> { where(archived_at: nil) }
  scope :for_user, ->(user) { where(user: user) }
  scope :ordered, -> { order(:name) }
  # Auto-created places nothing holds on to any more, so they can be removed.
  scope :orphaned, lambda {
    holders = [
      Visit.active.where('visits.place_id = places.id'),
      Tagging.where(taggable_type: 'Place').where('taggings.taggable_id = places.id'),
      LegacyAreaPlaceMapping.where('legacy_area_place_mappings.place_id = places.id'),
      Note.where(attachable_type: 'Place').where('notes.attachable_id = places.id'),
      Achievements::Selection.where('achievement_selections.place_id = places.id'),
      Home.where('homes.place_id = places.id')
    ]
    candidates = photon.not_archived.where(name_locked_at: nil, geofence: false)
                       .where("NULLIF(BTRIM(places.note), '') IS NULL")
    holders.reduce(candidates) { |scope, holder| scope.where.not(holder.arel.exists) }
  }
  scope :containing, lambda { |latitude, longitude|
    where(
      'ST_DWithin(places.lonlat::geography, ' \
      'ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography, places.visit_radius)',
      longitude, latitude
    )
  }
  scope :linked_to_confirmed_visits, lambda { |user|
    where(id: user.visits.active.confirmed.where.not(place_id: nil).select(:place_id))
  }
  scope :imported, -> { where(source: sources[:gpx_waypoint]) }
  scope :tagged, -> { where(id: Tagging.where(taggable_type: 'Place').select(:taggable_id)) }
  scope :noted, lambda {
    where("NULLIF(BTRIM(places.note), '') IS NOT NULL")
      .or(where(id: Note.where(attachable_type: 'Place').select(:attachable_id)))
  }
  scope :with_home, -> { where(id: Home.select(:place_id)) }
  scope :confirmed_for, lambda { |user|
    manual.or(imported).or(linked_to_confirmed_visits(user)).or(tagged).or(noted).or(geofences).or(archived)
          .or(with_home)
  }
  scope :unconfirmed_for, ->(user) { where.not(id: confirmed_for(user).select(:id)) }
  scope :map_visible, ->(user) { confirmed_for(user).not_archived }

  def self.normalize_visit_radius(value)
    radius = value.to_i
    radius.positive? ? [radius, MAX_VISIT_RADIUS].min : column_defaults['visit_radius']
  end

  def self.attribution_for(latitude, longitude, search_radius: maximum(:visit_radius).to_i)
    return if search_radius <= 0

    not_archived.near([latitude, longitude], search_radius, :m)
                .containing(latitude, longitude)
                .min_by do |place|
                  distance = Geocoder::Calculations.distance_between([latitude, longitude], [place.lat, place.lon])
                  [place.visit_radius, distance, place.id]
                end
  end

  # Legacy places predate the lonlat column and carry coordinates only in the
  # decimal columns; to_f keeps their JSON serialization numeric — BigDecimal
  # would encode as a string.
  def lon
    lonlat&.x || longitude.to_f
  end

  def lat
    lonlat&.y || latitude.to_f
  end

  def legacy_area_id
    legacy_area_place_mappings.map(&:area_id).min
  end

  # Only hidden visits (tombstones/declines) can still reference orphans;
  # detach them so the FK allows the delete. Their dedup role survives:
  # Visit#center falls back to the visit's own points.
  def self.delete_orphans(ids)
    transaction do
      Visit.where(place_id: ids).update_all(place_id: nil)
      PlaceVisit.where(place_id: ids).delete_all
      where(id: ids).delete_all
    end
  end

  def archived?
    archived_at.present?
  end

  def archived=(value)
    self.archived_at = ActiveModel::Type::Boolean.new.cast(value) ? (archived_at || Time.current) : nil
  end

  def name_locked?
    name_locked_at.present?
  end

  def carry_name_to_visits(previous_name)
    stale_names = [previous_name, DEFAULT_NAME].compact.uniq - [name]
    return if stale_names.empty?

    visits.where(name: stale_names).update_all(name: nil, updated_at: Time.current)
  end

  def osm_id
    geodata.dig('properties', 'osm_id')
  end

  # "Street 12, 04275 City" from the geocoder properties, or nil without them.
  def address_line
    properties = Geocoding::ResultNormalizer.from_data(geodata)[:properties]
    street = [properties['street'], properties['housenumber']].compact_blank.join(' ')
    locality = [properties['postcode'], properties['city']].compact_blank.join(' ')
    [street, locality].compact_blank.join(', ').presence
  end

  def osm_key
    geodata.dig('properties', 'osm_key')
  end

  def osm_value
    geodata.dig('properties', 'osm_value')
  end

  def osm_type
    geodata.dig('properties', 'osm_type')
  end

  private

  def build_lonlat
    self.lonlat = "POINT(#{longitude} #{latitude})"
  end

  def lock_name_on_user_edit
    return if machine_named
    return unless will_save_change_to_name?

    return self.name_locked_at = nil if name == DEFAULT_NAME
    return if new_record? && !user_named

    self.name_locked_at = Time.current
  end

  def suggested_visit_reattribution_needed?
    return false if skip_suggested_visit_reattribution
    return !!reattribute_suggested_visits_on_create if previously_new_record?

    saved_change_to_latitude? || saved_change_to_longitude? ||
      saved_change_to_visit_radius? || saved_change_to_archived_at?
  end

  def schedule_suggested_visit_reattribution
    Places::ReattributeSuggestedVisitsJob.perform_later(user_id, id)
  end
end
