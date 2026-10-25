# frozen_string_literal: true

class Users::PrivacyZones
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
    bearing, fraction = shift_seed(place.id, radius)
    shift = radius * (MIN_SHIFT + ((MAX_SHIFT - MIN_SHIFT) * fraction))
    lat, lon = Geocoder::Calculations.endpoint([place.latitude.to_f, place.longitude.to_f], bearing, shift / 1000.0,
                                               units: :km)

    { place_id: place.id, lat:, lon: ((lon + 180) % 360) - 180, radius: ((radius + shift) * RADIUS_MARGIN).ceil }
  end

  def self.shift_seed(place_id, radius)
    digest = OpenSSL::HMAC.digest('SHA256', Rails.application.secret_key_base, "privacy-zone:#{place_id}:#{radius}")
    first, second = digest.unpack('NN')
    [first / 2.0**32 * 360, second / 2.0**32]
  end
  private_class_method :shift_seed
end
