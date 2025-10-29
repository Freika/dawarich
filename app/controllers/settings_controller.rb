# frozen_string_literal: true

class SettingsController < ApplicationController
  before_action :authenticate_user!
  before_action :authenticate_active_user!, only: %i[update]

  def index; end

  def update
    existing_settings = current_user.safe_settings.settings

    current_user.update(settings: existing_settings.merge(settings_params))

    flash.now[:notice] = 'Settings updated'

    redirect_to settings_path, notice: 'Settings updated'
  end

  def theme
    current_user.update(theme: params[:theme])

    redirect_back(fallback_location: root_path)
  end

  def generate_api_key
    current_user.update(api_key: SecureRandom.hex)

    redirect_back(fallback_location: root_path)
  end

  def disconnect_patreon
    if current_user.disconnect_patreon!
      redirect_to settings_path, notice: 'Patreon account disconnected successfully'
    else
      redirect_to settings_path, alert: 'Unable to disconnect Patreon account'
    end
  end

  private

  def settings_params
    params.require(:settings).permit(
      :meters_between_routes, :minutes_between_routes, :fog_of_war_meters,
      :time_threshold_minutes, :merge_threshold_minutes, :route_opacity,
      :immich_url, :immich_api_key, :photoprism_url, :photoprism_api_key,
      :visits_suggestions_enabled
    )
  end
end
