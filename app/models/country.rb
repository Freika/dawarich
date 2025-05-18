# frozen_string_literal: true

class Country < ApplicationRecord
  validates :name, :iso_a2, :iso_a3, :geom, presence: true

  def self.containing_point(lon, lat)
    where("ST_Contains(geom, ST_SetSRID(ST_MakePoint(?, ?), 4326))", lon, lat)
    .select(:id, :name, :iso_a2, :iso_a3)
    .first
  end

  def self.names_to_iso_a2
    pluck(:name, :iso_a2).to_h
  end
end
