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

  def photos
    return [] unless can_fetch_photos?

    filtered_photos.sample(12)
                         .sort_by { |photo| photo['localDateTime'] }
                         .map { |asset| photo_thumbnail(asset) }
  end

  def photos_sources
    filtered_photos.map { _1[:source] }.uniq
  end

  private

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

  def can_fetch_photos?
    user.immich_integration_configured? || user.photoprism_integration_configured?
  end

  def filtered_photos
    return @filtered_photos if defined?(@filtered_photos)

    photos = Photos::Search.new(
      user,
      start_date: started_at.to_date.to_s,
      end_date: ended_at.to_date.to_s
    ).call

    @filtered_photos = select_dominant_orientation(photos)
  end

  def select_dominant_orientation(photos)
    vertical_photos = photos.select { |photo| photo[:orientation] == 'portrait' }
    horizontal_photos = photos.select { |photo| photo[:orientation] == 'landscape' }

    vertical_photos.count > horizontal_photos.count ? vertical_photos : horizontal_photos
  end

  def photo_thumbnail(asset)
    { url: "/api/v1/photos/#{asset[:id]}/thumbnail.jpg?api_key=#{user.api_key}&source=#{asset[:source]}" }
  end
end

