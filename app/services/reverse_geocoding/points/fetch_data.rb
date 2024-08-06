# frozen_string_literal: true

class ReverseGeocoding::Points::FetchData
  attr_reader :point

  def initialize(point_id)
    @point = Point.find(point_id)
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error("Point with id #{point_id} not found: #{e.message}")
  end

  def call
    return if reverse_geocoded?

    response = Geocoder.search([point.latitude, point.longitude]).first
    return if response.blank? || response.data['error'].present?

    point.update!(city: response.city, country: response.country, geodata: response.data)
  end

  private

  def reverse_geocoded?
    point.city.present? && point.country.present? || point.geodata.present?
  end
end
