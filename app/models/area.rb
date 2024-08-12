# frozen_string_literal: true

class Area < ApplicationRecord
  reverse_geocoded_by :latitude, :longitude

  belongs_to :user
  has_many :visits, dependent: :destroy

  validates :name, :latitude, :longitude, :radius, presence: true

  def center = [latitude.to_f, longitude.to_f]
end
