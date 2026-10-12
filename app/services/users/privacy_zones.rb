# frozen_string_literal: true

class Users::PrivacyZones
  def initialize(user)
    @user = user
  end

  def call
    @user.tags.privacy_zones.includes(:places).flat_map do |tag|
      tag.places.map do |place|
        { lon: place.longitude.to_f, lat: place.latitude.to_f, radius: tag.privacy_radius_meters }
      end
    end
  end
end
