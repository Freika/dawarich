# frozen_string_literal: true

class Api::V1::LocationsController < ApiController
  before_action :validate_search_params, only: [:index]
  before_action :validate_suggestion_params, only: [:suggestions]

  def index
    if coordinate_search?
      search_results = LocationSearch::PointFinder.new(current_api_user, search_params).call

      render json: Api::LocationSearchResultSerializer.new(search_results).call
    else
      render json: { error: I18n.t('controllers.api.v1.locations.coordinates_lat_lon_are_required') },
             status: :bad_request
    end
  rescue StandardError => e
    Rails.logger.error "Location search error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    render json: { error: I18n.t('controllers.api.v1.locations.search_failed_please_try_again') },
           status: :internal_server_error
  end

  def suggestions
    if search_query.present? && search_query.length >= 2
      suggestions = LocationSearch::GeocodingService.new(search_query).search

      # Format suggestions for the frontend
      formatted_suggestions = suggestions.map do |suggestion|
        {
          name: suggestion[:name],
          address: suggestion[:address],
          coordinates: [suggestion[:lat], suggestion[:lon]],
          type: suggestion[:type]
        }
      end

      render json: { suggestions: formatted_suggestions }
    else
      render json: { suggestions: [] }
    end
  rescue StandardError => e
    Rails.logger.error "Suggestions error: #{e.message}"
    render json: { suggestions: [] }
  end

  private

  def search_query
    params[:q]&.strip
  end

  def search_params
    {
      latitude: params[:lat]&.to_f,
      longitude: params[:lon]&.to_f,
      limit: params[:limit]&.to_i || 50,
      date_from: parse_date(params[:date_from]),
      date_to: parse_date(params[:date_to]),
      radius_override: params[:radius_override]&.to_i
    }
  end

  def coordinate_search?
    params[:lat].present? && params[:lon].present?
  end

  def validate_search_params
    unless coordinate_search?
      render json: { error: I18n.t('controllers.api.v1.locations.coordinates_lat_lon_are_required') },
             status: :bad_request
      return false
    end

    lat = params[:lat]&.to_f
    lon = params[:lon]&.to_f

    if lat.abs > 90 || lon.abs > 180
      render json: { error: I18n.t('controllers.api.v1.locations.invalid_coordinates_lat_must_be_90_90_lon_must_be') },
             status: :bad_request
      return false
    end

    true
  end

  def validate_suggestion_params
    if search_query.present? && search_query.length > 200
      render json: { error: I18n.t('controllers.api.v1.locations.search_query_too_long_max_200_characters') },
             status: :bad_request
      return false
    end

    true
  end

  def parse_date(date_string)
    return nil if date_string.blank?

    Date.parse(date_string)
  rescue ArgumentError
    nil
  end
end
