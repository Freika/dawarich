# frozen_string_literal: true

class Api::UserSerializer
  def initialize(user)
    @user = user
  end

  def call
    {
      user: {
        email:     user.email,
        theme:     user.theme,
        created_at: user.created_at,
        updated_at: user.updated_at,
        settings: settings,
      }
    }
  end

  private

  attr_reader :user

  def settings
    {
      maps: user.safe_settings.maps,
      fog_of_war_meters: user.safe_settings.fog_of_war_meters.to_i,
      meters_between_routes: user.safe_settings.meters_between_routes.to_i,
      preferred_map_layer: user.safe_settings.preferred_map_layer,
      speed_colored_routes: user.safe_settings.speed_colored_routes,
      points_rendering_mode: user.safe_settings.points_rendering_mode,
      minutes_between_routes: user.safe_settings.minutes_between_routes.to_i,
      time_threshold_minutes: user.safe_settings.time_threshold_minutes.to_i,
      merge_threshold_minutes: user.safe_settings.merge_threshold_minutes.to_i,
      live_map_enabled: user.safe_settings.live_map_enabled,
      route_opacity: user.safe_settings.route_opacity.to_f,
      immich_url: user.safe_settings.immich_url,
      photoprism_url: user.safe_settings.photoprism_url,
      visits_suggestions_enabled: user.safe_settings.visits_suggestions_enabled?,
      speed_color_scale: user.safe_settings.speed_color_scale,
      fog_of_war_threshold: user.safe_settings.fog_of_war_threshold
    }
  end
end
