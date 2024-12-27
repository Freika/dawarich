# frozen_string_literal: true

class ReverseGeocoding::Points::FetchData
  attr_reader :point

  def initialize(point_id)
    @point = Point.find(point_id)
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error("Point with id #{point_id} not found: #{e.message}")
  end

  def call
    return if point.reverse_geocoded?

    update_point_with_geocoding_data
  end

  private

  def update_point_with_geocoding_data
    response = Geocoder.search([point.latitude, point.longitude]).first
    return if response.blank? || response.data['error'].present?

    country = Country.find_or_create_by(name: response.country, iso2_code: response.countrycode)
    city = City.find_or_create_by(name: response.city, country: country)
    county = County.find_or_create_by(name: response.county, country: country)
    state = State.find_or_create_by(name: response.state, country: country)

    point.update!(
      city: city,
      country: country,
      county: county,
      state: state,
      geodata: response.data,
      reverse_geocoded_at: Time.current
    )
  end
end
