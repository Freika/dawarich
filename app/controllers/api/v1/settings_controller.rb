# frozen_string_literal: true

class Api::V1::SettingsController < ApiController
  before_action :authenticate_active_api_user!, only: %i[update transportation_recalculation_status]

  def index
    render json: {
      settings: current_api_user.safe_settings.config,
      status: 'success'
    }, status: :ok
  end

  # NOTE: For Lite plan users, Pro-only settings (gated map layers, globe_projection)
  # are silently stripped before persistence by TransportationThresholdsUpdater.
  # The response reflects the filtered state via safe_settings.config.
  def update
    settings = settings_params
    unless valid_tiles_url?(settings)
      return render json: {
        message: 'Something went wrong',
        errors: ['Tile URL must include {z}, {x}, and {y} placeholders']
      }, status: :unprocessable_content
    end

    result = Users::TransportationThresholdsUpdater.new(current_api_user, settings).call

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

  PRO_ONLY_KEYS = %i[immich_url immich_api_key photoprism_url photoprism_api_key].freeze
  VALID_DISTANCE_UNITS = %w[km mi].freeze

  # Map customization is preview-only on the Lite plan: the panel lets Lite
  # users play with these live, but nothing persists (self-hosted and Pro
  # users are unaffected — plan_restricted? is false for them).
  MAP_CUSTOMIZATION_KEYS = %i[maps_maplibre_custom_theme maps_maplibre_tiles_url
                              route_color track_color].freeze
  TILE_URL_PLACEHOLDERS = %w[{z} {x} {y}].freeze

  def settings_params
    permitted = params.require(:settings).permit(
      :timezone,
      :meters_between_routes, :minutes_between_routes, :fog_of_war_meters,
      :time_threshold_minutes, :merge_threshold_minutes, :route_opacity,
      :route_color, :track_color,
      :preferred_map_layer, :points_rendering_mode, :live_map_enabled,
      :immich_url, :immich_api_key, :photoprism_url, :photoprism_api_key,
      :speed_colored_routes, :speed_color_scale, :fog_of_war_threshold, :fog_of_war_mode,
      :maps_v2_style, :maps_maplibre_style, :maps_maplibre_tiles_url, :globe_projection,
      :transportation_expert_mode,
      :min_minutes_spent_in_city, :max_gap_minutes_in_city,
      :stay_max_gap_minutes,
      :gps_filtering_enabled, :gps_accuracy_threshold,
      enabled_map_layers: [],
      places_tag_filters: [],
      enabled_transportation_modes: [],
      maps_maplibre_custom_theme: [
        :base,
        { tokens: %i[bg water parks buildings railway boundaries
                     road_motorway road_primary road_secondary
                     road_tertiary road_residential road_default] }
      ],
      maps: [:distance_unit, { hidden_tile_categories: [], disabled_poi_groups: [] }],
      transportation_thresholds: %i[walking_max_speed cycling_max_speed driving_max_speed flying_min_speed],
      transportation_expert_thresholds: %i[stationary_max_speed running_vs_cycling_accel cycling_vs_driving_accel
                                           train_min_speed min_segment_duration time_gap_threshold
                                           min_flight_distance_km]
    )

    if permitted[:maps].is_a?(ActionController::Parameters)
      permitted[:maps].delete(:distance_unit) unless VALID_DISTANCE_UNITS.include?(permitted[:maps][:distance_unit])
    elsif permitted.key?(:maps)
      permitted.delete(:maps)
    end

    if permitted.key?(:maps_maplibre_tiles_url) && permitted[:maps_maplibre_tiles_url].is_a?(String)
      permitted[:maps_maplibre_tiles_url] = permitted[:maps_maplibre_tiles_url].strip.presence
    end

    # Strip Pro-only integration keys for Lite cloud users. Self-hosted
    # users always have full access (`plan_restricted?` returns false).
    if current_api_user.plan_restricted?
      permitted = permitted.except(*PRO_ONLY_KEYS, *MAP_CUSTOMIZATION_KEYS)
      permitted = permitted.except(:maps_maplibre_style) if permitted[:maps_maplibre_style] == 'custom'
    end

    permitted
  end

  def valid_tiles_url?(settings)
    url = settings[:maps_maplibre_tiles_url]
    return true if url.nil?
    return false unless url.is_a?(String)

    TILE_URL_PLACEHOLDERS.all? { |placeholder| url.include?(placeholder) }
  end
end
