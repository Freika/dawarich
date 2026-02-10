# frozen_string_literal: true

class Area < ApplicationRecord
  include Notable

  reverse_geocoded_by :latitude, :longitude

  belongs_to :user
  has_many :visits, dependent: :destroy

  validates :name, :latitude, :longitude, :radius, presence: true

  alias_attribute :lon, :longitude
  alias_attribute :lat, :latitude

  def center = [latitude.to_f, longitude.to_f]
end
