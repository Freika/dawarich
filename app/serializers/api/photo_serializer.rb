# frozen_string_literal: true

class Api::PhotoSerializer
  def initialize(photo)
    @photo = photo
  end

  def call
    {
      id: id,
      latitude: latitude,
      longitude: longitude,
      localDateTime: local_date_time,
      originalFileName: original_file_name,
      city: city,
      state: state,
      country: country,
      type: type
    }
  end

  private

  attr_reader :photo

  def id
    photo['id'] || photo['ID']
  end

  def latitude
    photo.dig('exifInfo', 'latitude') || photo['Lat']
  end

  def longitude
    photo.dig('exifInfo', 'longitude') || photo['Lng']
  end

  def local_date_time
    photo['localDateTime'] || photo['TakenAtLocal']
  end

  def original_file_name
    photo['originalFileName'] || photo['OriginalName']
  end

  def city
    photo.dig('exifInfo', 'city') || photo['PlaceCity']
  end

  def state
    photo.dig('exifInfo', 'state') || photo['PlaceState']
  end

  def country
    photo.dig('exifInfo', 'country') || photo['PlaceCountry']
  end

  def type
    (photo['type'] || photo['Type']).downcase
  end
end
