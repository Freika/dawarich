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
      :meters_between_routes, :minutes_between_routes, :fog_of_war_meters,
      :time_threshold_minutes, :merge_threshold_minutes, :route_opacity,
      :immich_url, :immich_api_key, :immich_skip_ssl_verification,
      :photoprism_url, :photoprism_api_key, :photoprism_skip_ssl_verification,
      :visits_suggestions_enabled, :transportation_expert_mode,
      transportation_thresholds: %i[walking_max_speed cycling_max_speed driving_max_speed flying_min_speed],
      transportation_expert_thresholds: %i[stationary_max_speed running_vs_cycling_accel cycling_vs_driving_accel
                                           train_min_speed min_segment_duration time_gap_threshold
                                           min_flight_distance_km]
    )
  end
end
