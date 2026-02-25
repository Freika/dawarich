# frozen_string_literal: true

class Api::V1::PhotosController < ApiController
  before_action :check_integration_configured, only: %i[index thumbnail]
  before_action :check_source, only: %i[thumbnail]

  def index
    cache_key = "photos_#{current_api_user.id}_#{params[:start_date]}_#{params[:end_date]}"
    cached_photos = Rails.cache.read(cache_key)
    return render json: cached_photos, status: :ok unless cached_photos.nil?

    search = Photos::Search.new(current_api_user, start_date: params[:start_date], end_date: params[:end_date])
    @photos = search.call
    Rails.cache.write(cache_key, @photos, expires_in: 30.minutes) if search.errors.blank?

    render json: @photos, status: :ok
  rescue StandardError => e
    Rails.logger.error("Photo search failed: #{e.message}")
    render json: { error: 'Failed to fetch photos' }, status: :bad_gateway
  end

  def thumbnail
    response = fetch_cached_thumbnail(params[:source])
    handle_thumbnail_response(response)
  end

  private

  def fetch_cached_thumbnail(source)
    cache_key = "photo_thumbnail_#{current_api_user.id}_#{source}_#{params[:id]}"
    cached_response = Rails.cache.read(cache_key)
    return cached_response if cached_response.present?

    response = Photos::Thumbnail.new(current_api_user, source, params[:id]).call
    Rails.cache.write(cache_key, response, expires_in: 30.minutes) if response.success?
    response
  end

  def handle_thumbnail_response(response)
    if response.success?
      send_data(response.body, type: 'image/jpeg', disposition: 'inline', status: :ok)
    else
      error_message = thumbnail_error(response)
      render json: { error: error_message }, status: response.code
    end
  end

  def thumbnail_error(response)
    return Immich::ResponseAnalyzer.new(response).error_message if params[:source] == 'immich'

    'Failed to fetch thumbnail'
  end

  def integration_configured?
    current_api_user.immich_integration_configured? || current_api_user.photoprism_integration_configured?
  end

  def check_integration_configured
    unauthorized_integration unless integration_configured?
  end

  def check_source
    unauthorized_integration unless %w[immich photoprism].include?(params[:source])
  end

  def unauthorized_integration
    render json: { error: "#{params[:source]&.capitalize} integration not configured" },
           status: :unauthorized
  end
end
