# frozen_string_literal: true

class Photos::Mappable
  MAX_PHOTOS = 100

  def initialize(photos, privacy_zones: [], max: MAX_PHOTOS)
    @photos = photos
    @privacy_zones = privacy_zones
    @max = max
  end

  def call
    @photos.select { |p| p[:latitude].present? && p[:longitude].present? }
           .reject { |p| within_privacy_zone?(p[:latitude], p[:longitude]) }
           .first(@max)
  end

  private

  def within_privacy_zone?(lat, lon)
    return false if lat.blank? || lon.blank?

    @privacy_zones.any? do |zone|
      distance_meters(lat.to_f, lon.to_f, zone[:lat], zone[:lon]) <= zone[:radius]
    end
  end

  def distance_meters(lat1, lon1, lat2, lon2)
    Geocoder::Calculations.distance_between([lat1, lon1], [lat2, lon2], units: :km) * 1000
  end
end
