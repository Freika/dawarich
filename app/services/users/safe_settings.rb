# frozen_string_literal: true

class Users::SafeSettings
  attr_reader :settings

  def initialize(settings)
    @settings = settings
  end

  # rubocop:disable Metrics/MethodLength
  def config
    {
      fog_of_war_meters: fog_of_war_meters,
      meters_between_routes: meters_between_routes,
      preferred_map_layer: preferred_map_layer,
      speed_colored_routes: speed_colored_routes,
      points_rendering_mode: points_rendering_mode,
      minutes_between_routes: minutes_between_routes,
      time_threshold_minutes: time_threshold_minutes,
      merge_threshold_minutes: merge_threshold_minutes,
      live_map_enabled: live_map_enabled,
      route_opacity: route_opacity,
      immich_url: immich_url,
      immich_api_key: immich_api_key,
      photoprism_url: photoprism_url,
      photoprism_api_key: photoprism_api_key,
      maps: maps
    }
  end
  # rubocop:enable Metrics/MethodLength

  def fog_of_war_meters
    settings['fog_of_war_meters'] || 50
  end

  def meters_between_routes
    settings['meters_between_routes'] || 500
  end

  def preferred_map_layer
    settings['preferred_map_layer'] || 'OpenStreetMap'
  end

  def speed_colored_routes
    settings['speed_colored_routes'] || false
  end

  def points_rendering_mode
    settings['points_rendering_mode'] || 'raw'
  end

  def minutes_between_routes
    settings['minutes_between_routes'] || 30
  end

  def time_threshold_minutes
    settings['time_threshold_minutes'] || 30
  end

  def merge_threshold_minutes
    settings['merge_threshold_minutes'] || 15
  end

  def live_map_enabled
    return settings['live_map_enabled'] if settings.key?('live_map_enabled')

    true
  end

  def route_opacity
    settings['route_opacity'] || 0.6
  end

  def immich_url
    settings['immich_url']
  end

  def immich_api_key
    settings['immich_api_key']
  end

  def photoprism_url
    settings['photoprism_url']
  end

  def photoprism_api_key
    settings['photoprism_api_key']
  end

  def maps
    settings['maps'] || {}
  end
end
