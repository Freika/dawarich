# frozen_string_literal: true

class Api::V1::SettingsController < ApiController
  before_action :authenticate_active_api_user!, only: %i[update transportation_recalculation_status]

  def index
    render json: {
      settings: current_api_user.safe_settings.config,
      status: 'success'
    }, status: :ok
  end

  def update
    result = Users::TransportationThresholdsUpdater.new(current_api_user, settings_params).call

    if result.success?
      render json: {
        message: 'Settings updated',
        settings: current_api_user.safe_settings.config,
        status: 'success',
        recalculation_triggered: result.recalculation_triggered?
      }, status: :ok
    elsif result.error&.include?('recalculation is in progress')
      render json: { message: result.error, status: 'locked' }, status: :locked
    else
      render json: { message: 'Something went wrong', errors: [result.error] }, status: :unprocessable_content
    end
  end

  def transportation_recalculation_status
    status = recalculation_status_manager.data
    render json: {
      status: status['status'],
      total_tracks: status['total_tracks'],
      processed_tracks: status['processed_tracks'],
      started_at: status['started_at'],
      completed_at: status['completed_at'],
      error_message: status['error_message']
    }, status: :ok
  end

  private

  def recalculation_status_manager
    @recalculation_status_manager ||= Tracks::TransportationRecalculationStatus.new(current_api_user.id)
  end

  def settings_params
    params.require(:settings).permit(
      :meters_between_routes, :minutes_between_routes, :fog_of_war_meters,
      :time_threshold_minutes, :merge_threshold_minutes, :route_opacity,
      :preferred_map_layer, :points_rendering_mode, :live_map_enabled,
      :immich_url, :immich_api_key, :photoprism_url, :photoprism_api_key,
      :speed_colored_routes, :speed_color_scale, :fog_of_war_threshold,
      :maps_v2_style, :maps_maplibre_style, :globe_projection,
      :transportation_expert_mode,
      :min_minutes_spent_in_city, :max_gap_minutes_in_city,
      enabled_map_layers: [],
      transportation_thresholds: %i[walking_max_speed cycling_max_speed driving_max_speed flying_min_speed],
      transportation_expert_thresholds: %i[stationary_max_speed running_vs_cycling_accel cycling_vs_driving_accel
                                           train_min_speed min_segment_duration time_gap_threshold
                                           min_flight_distance_km]
    )
  end
end
