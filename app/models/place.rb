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
  has_many :place_visits, dependent: :destroy
  has_many :suggested_visits, -> { distinct }, through: :place_visits, source: :visit

  before_validation :build_lonlat, if: -> { latitude.present? && longitude.present? }

  validates :name, presence: true, length: { maximum: 255 }
  validates :lonlat, presence: true

  enum :source, { manual: 0, photon: 1 }

  scope :for_user, ->(user) { where(user: user) }
  scope :ordered, -> { order(:name) }
  scope :linked_to_confirmed_visits, lambda { |user|
    where(id: user.visits.confirmed.where.not(place_id: nil).select(:place_id))
  }
  scope :tagged, -> { where(id: Tagging.where(taggable_type: 'Place').select(:taggable_id)) }
  scope :map_visible, lambda { |user|
    manual.or(linked_to_confirmed_visits(user)).or(tagged)
  }

  def lon
    lonlat.x
  end

  def lat
    lonlat.y
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
end
