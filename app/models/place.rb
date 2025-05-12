# frozen_string_literal: true

class Place < ApplicationRecord
  include Nearable
  include Distanceable

  DEFAULT_NAME = 'Suggested place'

  validates :name, :lonlat, presence: true

  has_many :visits, dependent: :destroy
  has_many :place_visits, dependent: :destroy
  has_many :suggested_visits, -> { distinct }, through: :place_visits, source: :visit

  enum :source, { manual: 0, photon: 1 }

  def lon
    lonlat.x
  end

  def lat
    lonlat.y
  end

  def reverse_geocoded?
    geodata.present?
  end

  def osm_id
    geodata['properties']['osm_id']
  end

  def osm_key
    geodata['properties']['osm_key']
  end

  def osm_value
    geodata['properties']['osm_value']
  end

  def osm_type
    geodata['properties']['osm_type']
  end
end
