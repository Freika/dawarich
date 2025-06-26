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

    country_record = Country.find_or_create_by(name: response.country) do |country|
      country.iso_a2 = response.country[0..1].upcase if response.country
      country.iso_a3 = response.country[0..2].upcase if response.country
      country.geom = "MULTIPOLYGON (((0 0, 1 0, 1 1, 0 1, 0 0)))"
    end if response.country

    point.update!(
      city: response.city,
      country_id: country_record&.id,
      geodata: response.data,
      reverse_geocoded_at: Time.current
    )
  end
end
