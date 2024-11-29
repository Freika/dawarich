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
    return [] if user.settings['immich_url'].blank? || user.settings['immich_api_key'].blank?

    immich_photos = Immich::RequestPhotos.new(
      user,
      start_date: started_at.to_date.to_s,
      end_date: ended_at.to_date.to_s
    ).call.reject { |asset| asset['type'].downcase == 'video' }

    # let's count what photos are more: vertical or horizontal and select the ones that are more
    vertical_photos = immich_photos.select { _1['exifInfo']['orientation'] == '6' }
    horizontal_photos = immich_photos.select { _1['exifInfo']['orientation'] == '3' }

    # this is ridiculous, but I couldn't find my way around frontend
    # to show all photos in the same height
    photos = vertical_photos.count > horizontal_photos.count ? vertical_photos : horizontal_photos

    photos.sample(12).sort_by { _1['localDateTime'] }.map do |asset|
      { url: "/api/v1/photos/#{asset['id']}/thumbnail.jpg?api_key=#{user.api_key}" }
    end
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
end
