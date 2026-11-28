# frozen_string_literal: true

# Finds an imported place by the name and coordinates an export recorded for it.
module Users::ImportData::PlaceLookup
  COORDINATE_TOLERANCE = 0.0001

  private

  def find_place_by_reference(name, latitude, longitude)
    latitude = latitude&.to_f
    longitude = longitude&.to_f
    return nil unless name.present? && latitude.present? && longitude.present?

    user.places.find_by(name: name, latitude: latitude, longitude: longitude) ||
      user.places.where(
        'latitude BETWEEN ? AND ? AND longitude BETWEEN ? AND ?',
        latitude - COORDINATE_TOLERANCE, latitude + COORDINATE_TOLERANCE,
        longitude - COORDINATE_TOLERANCE, longitude + COORDINATE_TOLERANCE
      ).first
  end
end
