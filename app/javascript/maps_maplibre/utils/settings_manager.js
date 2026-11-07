/**
 * Settings manager for persisting user preferences
 * Loads settings from backend API only (no localStorage)
 */

import { classifyBasemapUrl } from "maps_maplibre/utils/basemap_url"

// Every default lives on the server (Users::SafeSettings): the map reads
// effective values from /api/v1/settings and keeps none of its own.

export const LAYER_NAME_MAP = {
  Points: "pointsVisible",
  Heatmap: "heatmapEnabled",
  Hexagons: "hexagonsEnabled",
  Visits: "visitsEnabled",
  Photos: "photosEnabled",
  Tracks: "tracksEnabled",
  Flights: "flightsEnabled",
  "Fog of War": "fogEnabled",
  "Scratch map": "scratchEnabled",
  "Family Members": "familyEnabled",
  Places: "placesEnabled",
  "Place boundaries": "placeBoundariesEnabled",
  Anomalies: "anomaliesEnabled",
}

const BOOLEAN_SETTINGS = [
  "gpsFilteringEnabled",
  "gpsAccuracyFilterEnabled",
  "pointDraggingEnabled",
  "splitTracksAtMidnight",
  "globeProjection",
  "speedColoredRoutes",
  "liveMapEnabled",
  "tilesFallback",
]

export const BACKEND_SETTINGS_MAP = {
  mapStyle: "maps_maplibre_style",
  customTheme: "maps_maplibre_custom_theme",
  vectorTilesUrl: "maps_maplibre_tiles_url",
  tilesFallback: "maps_maplibre_tiles_fallback",
  trackColor: "track_color",
  enabledMapLayers: "enabled_map_layers",
  placesTagFilters: "places_tag_filters",
  fogOfWarRadius: "fog_of_war_meters",
  fogOfWarThreshold: "fog_of_war_threshold",
  fogOfWarMode: "fog_of_war_mode",
  globeProjection: "globe_projection",
  speedColoredRoutes: "speed_colored_routes",
  speedColorScale: "speed_color_scale",
  metersBetweenRoutes: "meters_between_routes",
  minutesBetweenRoutes: "minutes_between_routes",
  splitTracksAtMidnight: "split_tracks_at_midnight",
  minMinutesSpentInCity: "min_minutes_spent_in_city",
  gpsFilteringEnabled: "gps_filtering_enabled",
  gpsAccuracyFilterEnabled: "gps_accuracy_filter_enabled",
  gpsAccuracyThreshold: "gps_accuracy_threshold",
  pointDraggingEnabled: "point_dragging_enabled",
  enabledTransportationModes: "enabled_transportation_modes",
  distance_unit: "distance_unit",
  liveMapEnabled: "live_map_enabled",
}

// biome-ignore lint/complexity/noStaticOnlyClass: retain the established public API
export class SettingsManager {
  static apiKey = null
  static cachedSettings = null
  // False until settings load from the server; saving is refused meanwhile so
  // a partial snapshot can never overwrite the stored settings.
  static loaded = false
  static saveQueue = Promise.resolve()

  /**
   * Initialize settings manager with API key
   * @param {string} apiKey - User's API key for backend requests
   */
  static initialize(apiKey) {
    SettingsManager.apiKey = apiKey
    SettingsManager.cachedSettings = null
    SettingsManager.loaded = false
  }

  /**
   * Get the loaded settings; empty until they load from the server
   * @returns {Object} Settings object
   */
  static getSettings() {
    if (SettingsManager.cachedSettings) {
      return { ...SettingsManager.cachedSettings }
    }

    return SettingsManager._expandLayerSettings({})
  }

  /**
   * Convert enabled_map_layers array to individual boolean flags
   * @param {Object} settings - Settings with enabledMapLayers array
   * @returns {Object} Settings with individual layer booleans
   */
  static _expandLayerSettings(settings) {
    const enabledLayers = [...(settings.enabledMapLayers || [])]
    if (enabledLayers.includes("Routes") && !enabledLayers.includes("Tracks")) {
      enabledLayers.push("Tracks")
    }
    if (enabledLayers.includes("Areas")) {
      enabledLayers.push("Places", "Place boundaries")
    }
    settings.enabledMapLayers = [
      ...new Set(
        enabledLayers.filter((name) => name !== "Routes" && name !== "Areas"),
      ),
    ]

    Object.entries(LAYER_NAME_MAP).forEach(([layerName, settingKey]) => {
      settings[settingKey] = settings.enabledMapLayers.includes(layerName)
    })

    return settings
  }

  /**
   * Convert individual boolean flags to enabled_map_layers array
   * @param {Object} settings - Settings with individual layer booleans
   * @returns {Array} Array of enabled layer names
   */
  static _collapseLayerSettings(settings) {
    const enabledLayers = []

    Object.entries(LAYER_NAME_MAP).forEach(([layerName, settingKey]) => {
      if (settings[settingKey] === true) {
        enabledLayers.push(layerName)
      }
    })

    return enabledLayers
  }

  /**
   * Load settings from backend API
   * @returns {Promise<Object|null>} Settings, or null when loading failed
   */
  static async loadFromBackend() {
    if (!SettingsManager.apiKey) {
      console.warn("[Settings] API key not set, cannot load from backend")
      return null
    }

    try {
      const response = await fetch("/api/v1/settings", {
        headers: SettingsManager._headers(),
      })

      if (!response.ok) {
        throw new Error(`Failed to load settings: ${response.status}`)
      }

      const data = await response.json()
      return SettingsManager._applyBackendSettings(data.settings)
    } catch (error) {
      console.error("[Settings] Failed to load from backend:", error)
      return null
    }
  }

  static _headers() {
    return {
      Authorization: `Bearer ${SettingsManager.apiKey}`,
      "Content-Type": "application/json",
    }
  }

  /**
   * Map the server's effective settings to frontend keys and cache them
   * @param {Object} backendSettings - `settings` from the settings API
   * @returns {Object} Expanded frontend settings
   */
  static _applyBackendSettings(backendSettings) {
    const frontendSettings = {}
    Object.entries(BACKEND_SETTINGS_MAP).forEach(
      ([frontendKey, backendKey]) => {
        if (!(backendKey in backendSettings)) return

        let value = backendSettings[backendKey]
        if (BOOLEAN_SETTINGS.includes(frontendKey)) {
          value = value === true || value === "true"
        }
        frontendSettings[frontendKey] = value
      },
    )

    // Extract map customization from nested maps settings
    if (backendSettings.maps?.hidden_tile_categories) {
      frontendSettings.hiddenTileCategories =
        backendSettings.maps.hidden_tile_categories
    }
    if (backendSettings.maps?.disabled_poi_groups) {
      frontendSettings.disabledPoiGroups =
        backendSettings.maps.disabled_poi_groups
    }

    const expandedSettings =
      SettingsManager._expandLayerSettings(frontendSettings)

    SettingsManager.cachedSettings = expandedSettings
    SettingsManager.loaded = true

    return expandedSettings
  }

  /**
   * Update cache with new settings
   * @param {Object} settings - Settings object
   */
  static updateCache(settings) {
    SettingsManager.cachedSettings = { ...settings }
  }

  /**
   * Save settings to backend API
   * @param {Object} settings - Settings to save
   * @returns {Promise<Object|null>} API response data or null on failure
   */
  static async saveToBackend(settings) {
    if (!SettingsManager.apiKey) {
      console.warn("[Settings] API key not set, cannot save to backend")
      return null
    }
    if (!SettingsManager.loaded) {
      console.warn("[Settings] Settings not loaded, refusing to save")
      return null
    }

    try {
      const backendSettings = {}
      Object.entries(BACKEND_SETTINGS_MAP).forEach(
        ([frontendKey, backendKey]) => {
          if (frontendKey in settings) {
            let value = settings[frontendKey]

            if (
              frontendKey === "fogOfWarRadius" ||
              frontendKey === "fogOfWarThreshold" ||
              frontendKey === "metersBetweenRoutes" ||
              frontendKey === "minutesBetweenRoutes" ||
              frontendKey === "minMinutesSpentInCity"
            ) {
              value = parseInt(value, 10).toString()
            } else if (
              frontendKey === "globeProjection" ||
              frontendKey === "speedColoredRoutes"
            ) {
              value = Boolean(value)
            } else if (frontendKey === "liveMapEnabled") {
              value = Boolean(value)
            } else if (
              frontendKey === "pointDraggingEnabled" ||
              frontendKey === "splitTracksAtMidnight"
            ) {
              value = Boolean(value)
            }

            backendSettings[backendKey] = value
          }
        },
      )

      // distance_unit, tile categories, and POI groups live inside the
      // nested `maps` hash on the backend, the API merges it so the V1
      // keys managed by the settings page survive.
      delete backendSettings.distance_unit
      const mapsPayload = {}
      if (settings.distance_unit != null) {
        mapsPayload.distance_unit = settings.distance_unit
      }
      if (Array.isArray(settings.hiddenTileCategories)) {
        mapsPayload.hidden_tile_categories = settings.hiddenTileCategories
      }
      if (Array.isArray(settings.disabledPoiGroups)) {
        mapsPayload.disabled_poi_groups = settings.disabledPoiGroups
      }
      if (Object.keys(mapsPayload).length > 0) {
        backendSettings.maps = mapsPayload
      }

      const response = await fetch("/api/v1/settings", {
        method: "PATCH",
        headers: SettingsManager._headers(),
        body: JSON.stringify({ settings: backendSettings }),
      })

      const data = await response.json()

      if (!response.ok) {
        return data
      }

      return data
    } catch (error) {
      console.error("[Settings] Failed to save to backend:", error)
      return null
    }
  }

  /**
   * Get a specific setting
   * @param {string} key - Setting key
   * @returns {*} Setting value
   */
  static getSetting(key) {
    return SettingsManager.getSettings()[key]
  }

  static validVectorTilesUrl(url) {
    return !url || classifyBasemapUrl(url) !== null
  }

  /**
   * Update a specific setting and save to backend
   * @param {string} key - Setting key
   * @param {*} value - New value
   * @returns {Promise<Object|null>} API response data
   */
  static async updateSetting(key, value) {
    return await SettingsManager.updateSettings({ [key]: value })
  }

  static async updateSettings(updates) {
    const settings = SettingsManager.getSettings()
    Object.assign(settings, updates)

    const isLayerSetting = Object.keys(updates).some((key) =>
      Object.values(LAYER_NAME_MAP).includes(key),
    )
    if (isLayerSetting) {
      settings.enabledMapLayers =
        SettingsManager._collapseLayerSettings(settings)
    }

    SettingsManager.updateCache(settings)

    // Send only what changed: a full snapshot would re-store every default
    // and carry data rules such as transportation modes into each toggle.
    const changes = { ...updates }
    if (isLayerSetting) changes.enabledMapLayers = settings.enabledMapLayers

    const previousSave = SettingsManager.saveQueue.catch(() => null)
    const save = previousSave.then(() => SettingsManager.saveToBackend(changes))
    SettingsManager.saveQueue = save

    return await save
  }

  /**
   * Restore appearance settings to the server defaults
   * @param {string[]|null} keys - Backend keys to reset; all appearance settings when omitted
   * @returns {Promise<Object|null>} Settings after the reset, or null on failure
   */
  static async resetToDefaults(keys = null) {
    if (!SettingsManager.apiKey) return null

    const query = keys
      ? `?${keys.map((key) => `keys[]=${encodeURIComponent(key)}`).join("&")}`
      : ""
    const previousSave = SettingsManager.saveQueue.catch(() => null)
    const reset = previousSave.then(async () => {
      const response = await fetch(`/api/v1/settings/appearance${query}`, {
        method: "DELETE",
        headers: SettingsManager._headers(),
      })
      if (!response.ok) {
        throw new Error(`Failed to reset settings: ${response.status}`)
      }
      const data = await response.json()
      return SettingsManager._applyBackendSettings(data.settings)
    })
    SettingsManager.saveQueue = reset

    try {
      return await reset
    } catch (error) {
      console.error("[Settings] Failed to reset settings:", error)
      return null
    }
  }

  /**
   * Sync settings: load from backend
   * Call this on app initialization
   * @returns {Promise<Object>} Settings from backend, empty when loading failed
   */
  static async sync() {
    return (
      (await SettingsManager.loadFromBackend()) || SettingsManager.getSettings()
    )
  }
}
