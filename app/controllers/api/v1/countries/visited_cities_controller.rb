# frozen_string_literal: true

class Api::V1::Countries::VisitedCitiesController < ApiController
  include SafeTimestampParser

  before_action :validate_params

  def index
    start_at = safe_timestamp(params[:start_at])
    end_at = safe_timestamp(params[:end_at])

    points = current_api_user
             .points
             .without_raw_data
             .where(timestamp: start_at..end_at)

    render json: {
      data: CountriesAndCities.new(
        points,
        min_minutes_spent_in_city: current_api_user.safe_settings.min_minutes_spent_in_city,
        max_gap_minutes: current_api_user.safe_settings.max_gap_minutes_in_city
      ).call
    }
  end

  private

  def required_params
    %i[start_at end_at]
  end
end
