# frozen_string_literal: true

class Api::V1::FlightsController < ApiController
  MAX_FLIGHTS = 2_000

  def index
    flights = current_api_user.flights.mappable
    flights = apply_date_filter(flights)
    flights = flights.order(:departure_time).limit(MAX_FLIGHTS)

    render json: {
      type: 'FeatureCollection',
      features: flights.map { |flight| Api::FlightSerializer.new(flight).call }
    }
  end

  private

  def apply_date_filter(flights)
    return flights if params[:start_at].blank? && params[:end_at].blank?

    start_at = parse_time(params[:start_at]) || Time.zone.at(0)
    end_at = parse_time(params[:end_at]) || Time.zone.now
    flights.where(departure_time: start_at..end_at)
  end

  def parse_time(value)
    Time.zone.parse(value.to_s) if value.present?
  rescue ArgumentError
    nil
  end
end
