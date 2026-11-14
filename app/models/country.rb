# frozen_string_literal: true

class Country < ApplicationRecord
  has_many :points, dependent: :nullify

  validates :name, :iso_a2, :iso_a3, :geom, presence: true

  # A border runs up to ~2 MB, so lookups leave geom in the database.
  scope :without_geom, -> { select(:id, :name, :iso_a2, :iso_a3) }

  # Geocoder names and the seeded Natural Earth names disagree for a handful
  # of countries ("United States" vs "United States of America").
  def self.matching_name(name)
    return nil if name.blank?

    # Duplicate names resolve to the lowest id, matching the backfill's MIN(id).
    without_geom.where(name: Countries::NameAliases.canonical(name)).order(:id).first
  end

  def self.containing_point(lon, lat)
    without_geom.where('ST_Contains(geom, ST_SetSRID(ST_MakePoint(?, ?), 4326))', lon, lat).first
  end

  def self.names_to_iso_a2
    Rails.cache.fetch('countries_names_to_iso_a2', expires_in: 1.day) do
      pluck(:name, :iso_a2).to_h
    end
  end
end
