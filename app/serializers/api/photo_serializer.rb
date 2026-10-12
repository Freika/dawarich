# frozen_string_literal: true

class Api::PhotoSerializer
  def initialize(photo, source)
    @photo = photo.with_indifferent_access
    @source = source
  end

  def call
    {
      id: id,
      latitude: latitude,
      longitude: longitude,
      localDateTime: local_date_time,
      capturedAt: captured_at,
      originalFileName: original_file_name,
      city: city,
      state: state,
      country: country,
      type: type,
      orientation: orientation,
      source: source
    }
  end

  private

  attr_reader :photo, :source

  def id
    photo['id'] || photo['Hash']
  end

  def latitude
    photo.dig('exifInfo', 'latitude') || photo['Lat']
  end

  def longitude
    photo.dig('exifInfo', 'longitude') || photo['Lng']
  end

  def local_date_time
    case source
    when 'immich'
      photo['localDateTime']
    when 'photoprism'
      photo['TakenAtLocal']
    else
      photo['localDateTime'] || photo['TakenAtLocal']
    end
  end

  def captured_at
    case source
    when 'immich'
      photo['fileCreatedAt']
    when 'photoprism'
      photo['TakenAt']
    else
      photo['fileCreatedAt'] || photo['TakenAt']
    end
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

  def orientation
    case source
    when 'immich'
      photo.dig('exifInfo', 'orientation') == '6' ? 'portrait' : 'landscape'
    when 'photoprism'
      photo['Portrait'] ? 'portrait' : 'landscape'
    else
      'landscape' # default orientation for nil or unknown source
    end
  end
end
