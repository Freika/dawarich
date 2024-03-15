class ReverseGeocodingJob < ApplicationJob
  queue_as :default

  def perform(point_id)
    point = Point.find(point_id)
    return if point.city.present? && point.country.present?

    result = Geocoder.search([point.latitude, point.longitude])
    return if result.blank?

    point.update(
      city: result.first.city,
      country: result.first.country
    )
  end
end
