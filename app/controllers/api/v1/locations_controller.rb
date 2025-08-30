# frozen_string_literal: true

class Api::V1::LocationsController < ApiController
  before_action :validate_search_params, only: [:index]

  def index
    if search_query.present?
      search_results = LocationSearch::PointFinder.new(current_api_user, search_params).call
      render json: LocationSearchResultSerializer.new(search_results).call
    else
      render json: { error: 'Search query parameter (q) is required' }, status: :bad_request
    end
  rescue StandardError => e
    Rails.logger.error "Location search error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    render json: { error: 'Search failed. Please try again.' }, status: :internal_server_error
  end

  private

  def search_query
    params[:q]&.strip
  end

  def search_params
    {
      query: search_query,
      limit: params[:limit]&.to_i || 50,
      date_from: parse_date(params[:date_from]),
      date_to: parse_date(params[:date_to]),
      radius_override: params[:radius_override]&.to_i
    }
  end

  def validate_search_params
    if search_query.blank?
      render json: { error: 'Search query parameter (q) is required' }, status: :bad_request
      return false
    end

    if search_query.length > 200
      render json: { error: 'Search query too long (max 200 characters)' }, status: :bad_request
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