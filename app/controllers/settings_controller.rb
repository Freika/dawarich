# frozen_string_literal: true

class SettingsController < ApplicationController
  before_action :authenticate_user!

  def theme
    current_user.update(theme: params[:theme])

    redirect_back(fallback_location: root_path)
  end

  def generate_api_key
    current_user.update(api_key: SecureRandom.hex)

    redirect_back(fallback_location: root_path)
  end

  private

  def integration_settings_changed?(existing_settings, updated_settings, keys)
    keys.any? { |key| existing_settings[key] != updated_settings[key] }
  end

  def settings_params
    params.require(:settings).permit(
      :meters_between_routes, :minutes_between_routes, :fog_of_war_meters,
      :time_threshold_minutes, :merge_threshold_minutes, :route_opacity,
      :immich_url, :immich_api_key, :immich_skip_ssl_verification,
      :photoprism_url, :photoprism_api_key, :photoprism_skip_ssl_verification,
      :visits_suggestions_enabled, :transportation_expert_mode,
      :visit_detection_eps_meters, :visit_detection_min_points,
      :visit_detection_time_gap_minutes, :visit_detection_extended_merge_hours,
      :visit_detection_travel_threshold_meters, :visit_detection_default_accuracy,
      transportation_thresholds: %i[walking_max_speed cycling_max_speed driving_max_speed flying_min_speed],
      transportation_expert_thresholds: %i[stationary_max_speed running_vs_cycling_accel cycling_vs_driving_accel
                                           train_min_speed min_segment_duration time_gap_threshold
                                           min_flight_distance_km]
    )
  end
end
