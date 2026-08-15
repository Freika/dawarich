# frozen_string_literal: true

class Api::V1::PhotosController < ApiController
  THUMBNAIL_BROWSER_CACHE_MAX_AGE = 30.minutes

  before_action :check_integration_configured, only: %i[index thumbnail]
  before_action :check_source, only: %i[thumbnail]

  def index
    cache_key = "photos_#{current_api_user.id}_#{params[:start_date]}_#{params[:end_date]}"
    cached_photos = Rails.cache.read(cache_key)
    return render json: cached_photos, status: :ok if cached_photos.present?

    search = Photos::Search.new(current_api_user, start_date: params[:start_date], end_date: params[:end_date])
    @photos = search.call
    Rails.cache.write(cache_key, @photos, expires_in: 30.minutes) if search.errors.blank? && @photos.present?

    render json: @photos, status: :ok
  rescue StandardError => e
    Rails.logger.error("Photo search failed: #{e.message}")
    render json: { error: I18n.t('controllers.api.v1.photos.failed_to_fetch_photos') }, status: :bad_gateway
  end

  def thumbnail
    upstream = Photos::Thumbnail.new(current_api_user, params[:source], params[:id]).call
    handle_thumbnail_response(upstream)
  rescue *Photos::ConnectionErrors::HANDLED => e
    Rails.logger.error("Photo thumbnail fetch failed: #{e.message}")
    render json: { error: I18n.t('controllers.api.v1.photos.failed_to_fetch_photos') }, status: :bad_gateway
  end

  private

  def handle_thumbnail_response(upstream)
    if upstream.success?
      expires_in THUMBNAIL_BROWSER_CACHE_MAX_AGE, public: false
      send_data(upstream.body, type: 'image/jpeg', disposition: 'inline', status: :ok)
    else
      error_message = thumbnail_error(upstream)
      render json: { error: error_message }, status: upstream.code
    end
  end

  def thumbnail_error(response)
    return Immich::ResponseAnalyzer.new(response).error_message if params[:source] == 'immich'

    I18n.t('controllers.api.v1.photos.failed_to_fetch_thumbnail')
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
    error = I18n.t(
      'controllers.api.v1.photos.capitalize_integration_not_configured',
      source: params[:source]&.capitalize
    )
    render json: { error: error },
           status: :unauthorized
  end
end
