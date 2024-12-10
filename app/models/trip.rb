# frozen_string_literal: true

class Trip < ApplicationRecord
  has_rich_text :notes

  belongs_to :user

  validates :name, :started_at, :ended_at, presence: true

  before_save :calculate_distance

  def points
    user.tracked_points.where(timestamp: started_at.to_i..ended_at.to_i).order(:timestamp)
  end

  def countries
    points.pluck(:country).uniq.compact
  end

  def photo_previews
    @photo_previews ||= select_dominant_orientation(photos).sample(12)
  end

  def photo_sources
    @photo_sources ||= photos.map { _1[:source] }.uniq
  end

  private

  def photos
    @photos ||= Trips::Photos.new(self, user).call
  end

  def select_dominant_orientation(photos)
    vertical_photos = photos.select { |photo| photo[:orientation] == 'portrait' }
    horizontal_photos = photos.select { |photo| photo[:orientation] == 'landscape' }

    vertical_photos.count > horizontal_photos.count ? vertical_photos : horizontal_photos
  end

  def calculate_distance
    distance = 0

    points.each_cons(2) do |point1, point2|
      distance_between = Geocoder::Calculations.distance_between(
        point1.to_coordinates, point2.to_coordinates, units: ::DISTANCE_UNIT
      )

      distance += distance_between
    end

    self.distance = distance.round
  end
end
