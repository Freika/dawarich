# frozen_string_literal: true

class SettingsController < ApplicationController
  before_action :authenticate_user!
  before_action :authenticate_active_user!, only: %i[update]

  def index; end

  def update
    existing_settings = current_user.safe_settings.settings
    updated_settings = existing_settings.merge(settings_params)

    immich_changed = integration_settings_changed?(existing_settings, updated_settings, %w[immich_url immich_api_key])
    photoprism_changed = integration_settings_changed?(existing_settings, updated_settings,
                                                       %w[photoprism_url photoprism_api_key])

    unless current_user.update(settings: updated_settings)
      return redirect_to settings_path, alert: 'Settings could not be updated'
    end

    notices = ['Settings updated']
    alerts = []

    if params[:refresh_photos_cache].present?
      Photos::CacheCleaner.new(current_user).call
      notices << 'Photo cache refreshed'
    end

    if immich_changed
      result = Immich::ConnectionTester.new(
        updated_settings['immich_url'],
        updated_settings['immich_api_key'],
        skip_ssl_verification: updated_settings['immich_skip_ssl_verification']
      ).call
      result[:success] ? notices << result[:message] : alerts << result[:error]
    end

    if photoprism_changed
      result = Photoprism::ConnectionTester.new(
        updated_settings['photoprism_url'],
        updated_settings['photoprism_api_key'],
        skip_ssl_verification: updated_settings['photoprism_skip_ssl_verification']
      ).call
      result[:success] ? notices << result[:message] : alerts << result[:error]
    end

    flash[:notice] = notices.join('. ')
    flash[:alert] = alerts.join('. ') if alerts.any?

    redirect_to settings_path
  end

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
      transportation_thresholds: %i[walking_max_speed cycling_max_speed driving_max_speed flying_min_speed],
      transportation_expert_thresholds: %i[stationary_max_speed running_vs_cycling_accel cycling_vs_driving_accel
                                           train_min_speed min_segment_duration time_gap_threshold
                                           min_flight_distance_km]
    )
  end
end
