# frozen_string_literal: true

class Users::SafeSettings
  attr_reader :settings

  DEFAULT_VALUES = {
    'fog_of_war_meters' => 50,
    'meters_between_routes' => 500,
    'preferred_map_layer' => 'OpenStreetMap',
    'speed_colored_routes' => false,
    'points_rendering_mode' => 'raw',
    'minutes_between_routes' => 30,
    'time_threshold_minutes' => 30,
    'merge_threshold_minutes' => 15,
    'live_map_enabled' => true,
    'route_opacity' => 60,
    'immich_url' => nil,
    'immich_api_key' => nil,
    'immich_skip_ssl_verification' => false,
    'photoprism_url' => nil,
    'photoprism_api_key' => nil,
    'photoprism_skip_ssl_verification' => false,
    'maps' => { 'distance_unit' => 'km' },
    'visits_suggestions_enabled' => 'true',
    'enabled_map_layers' => %w[Routes Heatmap],
    'maps_maplibre_style' => 'light',
    'digest_emails_enabled' => true,
    'globe_projection' => false,
    # Transportation mode thresholds (speeds in km/h, distances in km)
    'transportation_thresholds' => {
      'walking_max_speed' => 7,
      'cycling_max_speed' => 45,
      'driving_max_speed' => 220,
      'flying_min_speed' => 150
    },
    'transportation_expert_thresholds' => {
      'stationary_max_speed' => 1,
      'running_vs_cycling_accel' => 0.25,
      'cycling_vs_driving_accel' => 0.4,
      'train_min_speed' => 80,
      'min_segment_duration' => 60,
      'time_gap_threshold' => 180,
      'min_flight_distance_km' => 100
    },
    'transportation_expert_mode' => false
  }.freeze

  def initialize(settings = {})
    @settings = DEFAULT_VALUES.dup.merge(settings)
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
      maps: maps,
      distance_unit: distance_unit,
      visits_suggestions_enabled: visits_suggestions_enabled?,
      speed_color_scale: speed_color_scale,
      fog_of_war_threshold: fog_of_war_threshold,
      enabled_map_layers: enabled_map_layers,
      maps_maplibre_style: maps_maplibre_style,
      globe_projection: globe_projection
    }
  end
  # rubocop:enable Metrics/MethodLength

  def fog_of_war_meters
    settings['fog_of_war_meters']
  end

  def meters_between_routes
    settings['meters_between_routes']
  end

  def preferred_map_layer
    settings['preferred_map_layer']
  end

  def speed_colored_routes
    settings['speed_colored_routes']
  end

  def points_rendering_mode
    settings['points_rendering_mode']
  end

  def minutes_between_routes
    settings['minutes_between_routes']
  end

  def time_threshold_minutes
    settings['time_threshold_minutes']
  end

  def merge_threshold_minutes
    settings['merge_threshold_minutes']
  end

  def live_map_enabled
    settings['live_map_enabled']
  end

  def route_opacity
    settings['route_opacity']
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

  def immich_skip_ssl_verification
    settings['immich_skip_ssl_verification']
  end

  def photoprism_skip_ssl_verification
    settings['photoprism_skip_ssl_verification']
  end

  def maps
    settings['maps']
  end

  def distance_unit
    settings.dig('maps', 'distance_unit')
  end

  def visits_suggestions_enabled?
    settings['visits_suggestions_enabled'] == 'true'
  end

  def speed_color_scale
    settings['speed_color_scale']
  end

  def fog_of_war_threshold
    settings['fog_of_war_threshold']
  end

  def enabled_map_layers
    settings['enabled_map_layers']
  end

  def maps_maplibre_style
    settings['maps_maplibre_style']
  end

  def globe_projection
    ActiveModel::Type::Boolean.new.cast(settings['globe_projection'])
  end

  def digest_emails_enabled?
    value = settings['digest_emails_enabled']
    return true if value.nil?

    ActiveModel::Type::Boolean.new.cast(value)
  end

  def transportation_thresholds
    settings['transportation_thresholds'] || DEFAULT_VALUES['transportation_thresholds']
  end

  def transportation_expert_thresholds
    settings['transportation_expert_thresholds'] || DEFAULT_VALUES['transportation_expert_thresholds']
  end

  def transportation_expert_mode?
    ActiveModel::Type::Boolean.new.cast(settings['transportation_expert_mode'])
  end

end
