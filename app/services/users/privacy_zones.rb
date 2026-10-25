# frozen_string_literal: true

class Users::PrivacyZones
  METERS_PER_DEGREE = 111_320.0
  MIN_SHIFT = 0.3
  MAX_SHIFT = 0.6
  RADIUS_MARGIN = 1.01

  def initialize(user)
    @user = user
  end

  def call
    @user.tags.privacy_zones.includes(:places).flat_map do |tag|
      tag.places.map { |place| self.class.circle(place, tag.privacy_radius_meters) }
    end
  end

  def self.circle(place, radius)
    lat = place.latitude.to_f
    lon = place.longitude.to_f
    bearing, fraction = shift_seed(place.id, radius)
    shift = radius * (MIN_SHIFT + ((MAX_SHIFT - MIN_SHIFT) * fraction))
    lon_scale = [Math.cos(lat * Math::PI / 180).abs, 0.01].max

    {
      place_id: place.id,
      lat: (lat + (shift * Math.cos(bearing) / METERS_PER_DEGREE)).clamp(-90.0, 90.0),
      lon: lon + (shift * Math.sin(bearing) / (METERS_PER_DEGREE * lon_scale)),
      radius: ((radius + shift) * RADIUS_MARGIN).ceil
    }
  end

  def self.shift_seed(place_id, radius)
    digest = OpenSSL::HMAC.digest('SHA256', Rails.application.secret_key_base, "privacy-zone:#{place_id}:#{radius}")
    first, second = digest.unpack('NN')
    [first / 2.0**32 * 2 * Math::PI, second / 2.0**32]
  end
  private_class_method :shift_seed
end
