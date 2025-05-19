# frozen_string_literal: true

class Trip < ApplicationRecord
  has_rich_text :notes

  belongs_to :user

  validates :name, :started_at, :ended_at, presence: true

  after_create :enqueue_calculation_jobs
  after_update :enqueue_calculation_jobs, if: -> { saved_change_to_started_at? || saved_change_to_ended_at? }

  def enqueue_calculation_jobs
    Trips::CalculateAllJob.perform_later(id, user.safe_settings.distance_unit)
  end

  def points
    user.tracked_points.where(timestamp: started_at.to_i..ended_at.to_i).order(:timestamp)
  end

  def countries
    return points.pluck(:country).uniq.compact if DawarichSettings.store_geodata?

    visited_countries
  end

  def photo_previews
    @photo_previews ||= select_dominant_orientation(photos).sample(12)
  end

  def photo_sources
    @photo_sources ||= photos.map { _1[:source] }.uniq
  end

  def calculate_path
    trip_path = Tracks::BuildPath.new(points.pluck(:lonlat)).call

    self.path = trip_path
  end

  def calculate_distance
    distance = Point.total_distance(points, user.safe_settings.distance_unit)

    self.distance = distance.round
  end

  def calculate_countries
    countries =
      Country.where(id: points.pluck(:country_id).compact.uniq).pluck(:name)

    self.visited_countries = countries
  end

  private

  def photos
    @photos ||= Trips::Photos.new(self, user).call
  end

  def select_dominant_orientation(photos)
    vertical_photos = photos.select { |photo| photo[:orientation] == 'portrait' }
    horizontal_photos = photos.select { |photo| photo[:orientation] == 'landscape' }

    # this is ridiculous, but I couldn't find my way around frontend
    # to show all photos in the same height
    vertical_photos.count > horizontal_photos.count ? vertical_photos : horizontal_photos
  end
end
