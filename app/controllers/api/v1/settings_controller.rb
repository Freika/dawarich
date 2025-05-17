# frozen_string_literal: true

class Api::V1::SettingsController < ApiController
  before_action :authenticate_active_api_user!, only: %i[update]

  def index
    render json: {
      settings: current_api_user.settings,
      status: 'success'
    }, status: :ok
  end

  def update
    settings_params.each { |key, value| current_api_user.settings[key] = value }

    if current_api_user.save
      render json: { message: 'Settings updated', settings: current_api_user.settings, status: 'success' },
             status: :ok
    else
      render json: { message: 'Something went wrong', errors: current_api_user.errors.full_messages },
             status: :unprocessable_entity
    end
  end

  private

  def settings_params
    params.require(:settings).permit(
      :meters_between_routes, :minutes_between_routes, :fog_of_war_meters,
      :time_threshold_minutes, :merge_threshold_minutes, :route_opacity,
      :preferred_map_layer, :points_rendering_mode, :live_map_enabled,
      :immich_url, :immich_api_key, :photoprism_url, :photoprism_api_key,
      :speed_colored_routes, :speed_color_scale, :fog_of_war_threshold
    )
  end
end
