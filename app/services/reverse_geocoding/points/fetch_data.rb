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
      iso_a2, iso_a3 = extract_iso_codes(response)
      country.iso_a2 = iso_a2
      country.iso_a3 = iso_a3
      country.geom = "MULTIPOLYGON (((0 0, 1 0, 1 1, 0 1, 0 0)))"
    end if response.country

    point.update!(
      city: response.city,
      country_id: country_record&.id,
      geodata: response.data,
      reverse_geocoded_at: Time.current
    )
  end

  def extract_iso_codes(response)
    # First, try to get the ISO A2 code from the Geocoder response
    iso_a2 = response.data.dig('properties', 'countrycode')&.upcase

    if iso_a2.present?
      # If we have a valid ISO A2 code, get the corresponding ISO A3 code
      iso_a3 = Countries::IsoCodeMapper.iso_a3_from_a2(iso_a2)
      return [iso_a2, iso_a3] if iso_a3.present?
    end

    # If no valid ISO code from Geocoder, try to match the country name
    # This will return proper ISO codes if the country name is recognized
    Countries::IsoCodeMapper.fallback_codes_from_country_name(response.country)
  end
end
