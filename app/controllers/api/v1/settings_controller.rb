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
  # are silently stripped before persistence by Users::SettingsUpdater.
  # The response reflects the filtered state via safe_settings.config.
  def update
    settings = settings_params
    unless valid_tiles_url?(settings)
      return render json: {
        message: I18n.t('controllers.api.v1.settings.something_went_wrong'),
        errors: [I18n.t('controllers.api.v1.settings.tile_url_error')]
      }, status: :unprocessable_content
    end

    result = Users::SettingsUpdater.new(current_api_user, settings).call

    if result.success?
      render json: {
        message: I18n.t('controllers.api.v1.settings.settings_updated'),
        settings: current_api_user.safe_settings.config,
        status: 'success',
        recalculation_triggered: result.recalculation_triggered?
      }, status: :ok
    elsif result.error&.include?('recalculation is in progress')
      render json: { message: result.error, status: 'locked' }, status: :locked
    else
      render json: { message: I18n.t('controllers.api.v1.settings.something_went_wrong'), errors: [result.error] },
             status: :unprocessable_content
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
  TILE_FILE_EXTENSIONS = %w[.png .jpg .jpeg .webp .mvt .pbf].freeze
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
      :min_minutes_spent_in_city, :max_gap_minutes_in_city,
      :gps_filtering_enabled,
      :point_dragging_enabled,
      enabled_map_layers: [],
      enabled_transportation_modes: [],
      maps_maplibre_custom_theme: [
        :base,
        { tokens: %i[bg water parks buildings railway boundaries
                     road_motorway road_primary road_secondary
                     road_tertiary road_residential road_default] }
      ],
      maps: [:distance_unit, { hidden_tile_categories: [], disabled_poi_groups: [] }]
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
    return true if style_document_url?(url)

    TILE_URL_PLACEHOLDERS.all? { |placeholder| url.include?(placeholder) }
  end

  # Mirrors classifyBasemapUrl in app/javascript/maps_maplibre/utils/basemap_url.js:
  # an absolute http(s) URL, or a root-relative path for a style served from
  # this instance. Keep the two in sync or the browser accepts a URL this
  # rejects.
  def style_document_url?(url)
    return false if url.match?(/[{}]/)

    locator = url.split(/[?#]/).first.to_s.downcase
    return false if TILE_FILE_EXTENSIONS.any? { |extension| locator.end_with?(extension) }

    uri = URI.parse(url)
    return uri.host.present? if uri.is_a?(URI::HTTP)

    uri.scheme.nil? && uri.host.nil? && uri.path.start_with?('/')
  rescue URI::InvalidURIError
    false
  end
end
