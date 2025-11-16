# frozen_string_literal: true

class Place < ApplicationRecord
  include Nearable
  include Distanceable
  include Taggable

  DEFAULT_NAME = 'Suggested place'

  belongs_to :user, optional: true # Optional during migration period
  has_many :visits, dependent: :destroy
  has_many :place_visits, dependent: :destroy
  has_many :suggested_visits, -> { distinct }, through: :place_visits, source: :visit

  validates :name, presence: true
  validates :latitude, :longitude, presence: true

  before_validation :build_lonlat, if: -> { latitude.present? && longitude.present? }

  enum :source, { manual: 0, photon: 1 }

  scope :for_user, ->(user) { where(user: user) }
  scope :ordered, -> { order(:name) }

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
