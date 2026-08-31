# frozen_string_literal: true

class Settings::IntegrationsController < ApplicationController
  FLASH_MESSAGE_BYTES = 512

  before_action :authenticate_user!
  before_action :authenticate_active_user!, only: %i[update]
  before_action :require_pro!, only: %i[update]

  def index
    @pro_required = !current_user.full_access?
    return if @pro_required

    @services = available_services
    @service = params[:service].presence_in(@services) || @services.first
    @statuses = Integrations::Status.for(current_user)

    prepare_geocoding if @service == 'geocoding'
  end

  def update
    result = Settings::Update.new(
      current_user,
      settings_params,
      refresh_photos_cache: params[:refresh_photos_cache].present?
    ).call

    flash[:notice] = flash_message(result[:notices]) if result[:notices].any?
    flash[:alert] = flash_message(result[:alerts]) if result[:alerts].any?

    redirect_to settings_integrations_path(service: params[:service].presence)
  end

  private

  def flash_message(messages)
    messages.join('. ').truncate_bytes(FLASH_MESSAGE_BYTES)
  end

  def available_services
    return Integrations::Status::SERVICES if DawarichSettings.self_hosted?

    Integrations::Status::PHOTO_SERVICES
  end

  def prepare_geocoding
    @settings_by_provider = current_user.service_settings.service_geocoding.index_by(&:provider)
    @geocoding_config = Geocoding::Config.for(current_user)
  end

  def settings_params
    params.require(:settings).permit(
      :immich_url, :immich_api_key, :immich_skip_ssl_verification,
      :photoprism_url, :photoprism_api_key, :photoprism_skip_ssl_verification,
      :airtrail_url, :airtrail_api_key, :airtrail_skip_ssl_verification
    )
  end
end
