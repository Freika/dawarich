# frozen_string_literal: true

module Users
  # What a Lite account may store and see. A Lite write never changes a
  # Pro-only setting, and the stored value stays put so an upgrade restores
  # it; a Lite read shows the Pro-only map settings at their defaults.
  module PlanSettingsGate
    GATED_MAP_LAYERS = ['Heatmap', 'Hexagons', 'Fog of War', 'Scratch map'].freeze

    # Shown to a Lite account as their defaults.
    MASKED_KEYS = %w[
      maps_maplibre_custom_theme maps_maplibre_tiles_url maps_maplibre_tiles_fallback
      route_color track_color
    ].freeze
    MASKED_MAPS_KEYS = %w[hidden_tile_categories disabled_poi_groups].freeze

    # Integrations stay readable so photos keep working after a downgrade.
    WRITE_ONLY_KEYS = %w[immich_url immich_api_key photoprism_url photoprism_api_key].freeze

    CUSTOM_STYLE = 'custom'

    module_function

    # The part of a Lite settings write that may be stored.
    def writable(params, stored)
      params = params.to_h.deep_stringify_keys.except(*MASKED_KEYS, *WRITE_ONLY_KEYS, 'globe_projection')
      params.delete('maps_maplibre_style') if params['maps_maplibre_style'] == CUSTOM_STYLE
      params['maps'] = params['maps'].except(*MASKED_MAPS_KEYS) if params['maps'].is_a?(Hash)
      if params.key?('enabled_map_layers')
        stored_gated = Array(stored['enabled_map_layers']) & GATED_MAP_LAYERS
        params['enabled_map_layers'] = (Array(params['enabled_map_layers']) - GATED_MAP_LAYERS) | stored_gated
      end
      params
    end

    # Settings as a Lite account sees them; `settings` already has defaults merged in.
    def visible(settings)
      settings = settings.merge(MASKED_KEYS.index_with { |key| SafeSettings::DEFAULT_VALUES[key].deep_dup })
      settings['globe_projection'] = false
      if settings['maps_maplibre_style'] == CUSTOM_STYLE
        settings['maps_maplibre_style'] = SafeSettings::DEFAULT_VALUES['maps_maplibre_style']
      end
      settings['enabled_map_layers'] = Array(settings['enabled_map_layers']) - GATED_MAP_LAYERS
      settings['maps'] = settings['maps'].except(*MASKED_MAPS_KEYS) if settings['maps'].is_a?(Hash)
      settings
    end
  end
end
