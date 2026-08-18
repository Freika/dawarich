# frozen_string_literal: true

class Place < ApplicationRecord
  include Demoable
  include Nearable
  include Distanceable
  include Taggable
  include Notable

  DEFAULT_NAME = 'Suggested place'

  belongs_to :user, optional: true # Optional until Stage 2 NOT NULL
  has_many :visits, dependent: :nullify
  # Reader surfaces (drawers, serializers, stats) must never count tombstoned
  # or declined visits; eager-loadable so list endpoints avoid N+1 counts.
  # dependent: nil — lifecycle belongs to the canonical :visits association.
  has_many :active_visits, -> { active }, class_name: 'Visit', inverse_of: :place, dependent: nil
  has_many :place_visits, dependent: :destroy
  has_many :suggested_visits, -> { distinct }, through: :place_visits, source: :visit

  attr_accessor :machine_named, :user_named

  before_validation :build_lonlat, if: -> { latitude.present? && longitude.present? }
  before_save :lock_name_on_user_edit

  validates :name, presence: true, length: { maximum: 255 }
  validates :lonlat, presence: true

  enum :source, { manual: 0, photon: 1 }

  scope :for_user, ->(user) { where(user: user) }
  scope :ordered, -> { order(:name) }
  scope :linked_to_confirmed_visits, lambda { |user|
    where(id: user.visits.active.confirmed.where.not(place_id: nil).select(:place_id))
  }
  scope :tagged, -> { where(id: Tagging.where(taggable_type: 'Place').select(:taggable_id)) }
  scope :map_visible, lambda { |user|
    manual.or(linked_to_confirmed_visits(user)).or(tagged)
  }

  # Legacy places predate the lonlat column and carry coordinates only in the
  # decimal columns; to_f keeps their JSON serialization numeric — BigDecimal
  # would encode as a string.
  def lon
    lonlat&.x || longitude.to_f
  end

  def lat
    lonlat&.y || latitude.to_f
  end

  def name_locked?
    name_locked_at.present?
  end

  def osm_id
    geodata.dig('properties', 'osm_id')
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
end
