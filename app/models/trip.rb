# frozen_string_literal: true

class Trip < ApplicationRecord
  belongs_to :user

  validates :name, :started_at, :ended_at, presence: true

  def points
    user.points.where(timestamp: started_at.to_i..ended_at.to_i).order(:timestamp)
  end

  def countries
    points.pluck(:country).uniq.compact
  end

  def photos
    immich_photos = Immich::RequestPhotos.new(
      user,
      start_date: started_at.to_date.to_s,
      end_date: ended_at.to_date.to_s
    ).call

    # let's count what photos are more: vertical or horizontal and select the ones that are more
    vertical_photos = immich_photos.select { _1['exifInfo']['orientation'] == '6' }
    horizontal_photos = immich_photos.select { _1['exifInfo']['orientation'] == '3' }

    # this is ridiculous, but I couldn't find my way around frontend
    # to show all photos in the same height
    photos = vertical_photos.count > horizontal_photos.count ? vertical_photos : horizontal_photos

    photos.sample(12).map do |asset|
      { url: "/api/v1/photos/#{asset['id']}/thumbnail.jpg?api_key=#{user.api_key}" }
    end
  end
end
