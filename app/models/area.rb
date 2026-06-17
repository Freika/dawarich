# frozen_string_literal: true

class Area < ApplicationRecord
  include Notable

  reverse_geocoded_by :latitude, :longitude

  belongs_to :user
  has_many :visits, dependent: :destroy

  validates :name, :latitude, :longitude, :radius, presence: true
  validates :radius, numericality: { greater_than: 0 }
  validates :latitude, numericality: { greater_than_or_equal_to: -90, less_than_or_equal_to: 90 }
  validates :longitude, numericality: { greater_than_or_equal_to: -180, less_than_or_equal_to: 180 }

  alias_attribute :lon, :longitude
  alias_attribute :lat, :latitude

  def center = [latitude.to_f, longitude.to_f]
end
