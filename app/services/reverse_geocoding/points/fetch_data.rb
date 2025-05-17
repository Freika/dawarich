# frozen_string_literal: true

class ReverseGeocoding::Points::FetchData
  attr_reader :point

  def initialize(point_id)
    @point = Point.find(point_id)
  rescue ActiveRecord::RecordNotFound => e
    ExceptionReporter.call(e)

    Rails.logger.error("Point with id #{point_id} not found: #{e.message}")
  end

  def call
    return if point.reverse_geocoded?

    update_point_with_geocoding_data
  end

  private

  def update_point_with_geocoding_data
    response = Geocoder.search([point.lat, point.lon]).first
    return if response.blank? || response.data['error'].present?

    point.update!(
      city: response.city,
      country: response.country,
      geodata: response.data,
      reverse_geocoded_at: Time.current
    )
  end
end
