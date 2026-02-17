# frozen_string_literal: true

class Settings::IntegrationsController < ApplicationController
  before_action :authenticate_user!
  before_action :authenticate_active_user!, only: %i[update]

  def index; end

  def update
    result = Settings::Update.new(
      current_user,
      settings_params,
      refresh_photos_cache: params[:refresh_photos_cache].present?
    ).call

    flash[:notice] = result[:notices].join('. ') if result[:notices].any?
    flash[:alert] = result[:alerts].join('. ') if result[:alerts].any?

    redirect_to settings_integrations_path
  end

  private

  def settings_params
    params.require(:settings).permit(
      :immich_url, :immich_api_key, :immich_skip_ssl_verification,
      :photoprism_url, :photoprism_api_key, :photoprism_skip_ssl_verification
    )
  end
end
