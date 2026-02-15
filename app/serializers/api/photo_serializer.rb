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
    case source
    when 'google_photos'
      # For Google Photos, use baseUrl as the ID since it's needed for thumbnails
      photo['baseUrl']
    else
      photo['id'] || photo['Hash']
    end
  end

  def latitude
    case source
    when 'google_photos'
      photo.dig('mediaMetadata', 'location', 'latitude')
    else
      photo.dig('exifInfo', 'latitude') || photo['Lat']
    end
  end

  def longitude
    case source
    when 'google_photos'
      photo.dig('mediaMetadata', 'location', 'longitude')
    else
      photo.dig('exifInfo', 'longitude') || photo['Lng']
    end
  end

  def local_date_time
    case source
    when 'google_photos'
      photo.dig('mediaMetadata', 'creationTime')
    else
      photo['localDateTime'] || photo['TakenAtLocal']
    end
  end

  def original_file_name
    case source
    when 'google_photos'
      photo['filename']
    else
      photo['originalFileName'] || photo['OriginalName']
    end
  end

  def city
    # Google Photos API doesn't provide reverse geocoded location names
    return nil if source == 'google_photos'

    photo.dig('exifInfo', 'city') || photo['PlaceCity']
  end

  def state
    # Google Photos API doesn't provide reverse geocoded location names
    return nil if source == 'google_photos'

    photo.dig('exifInfo', 'state') || photo['PlaceState']
  end

  def country
    # Google Photos API doesn't provide reverse geocoded location names
    return nil if source == 'google_photos'

    photo.dig('exifInfo', 'country') || photo['PlaceCountry']
  end

  def type
    case source
    when 'google_photos'
      'image' # Google Photos API filters for PHOTO type only
    else
      (photo['type'] || photo['Type'])&.downcase || 'image'
    end
  end

  def orientation
    case source
    when 'immich'
      photo.dig('exifInfo', 'orientation') == '6' ? 'portrait' : 'landscape'
    when 'photoprism'
      photo['Portrait'] ? 'portrait' : 'landscape'
    when 'google_photos'
      google_photos_orientation
    else
      'landscape' # default orientation for nil or unknown source
    end
  end

  def google_photos_orientation
    width = photo.dig('mediaMetadata', 'width')&.to_i || 0
    height = photo.dig('mediaMetadata', 'height')&.to_i || 0

    height > width ? 'portrait' : 'landscape'
  end
end
