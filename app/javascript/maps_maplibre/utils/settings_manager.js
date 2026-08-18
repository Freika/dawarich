/**
 * Settings manager for persisting user preferences
 * Loads settings from backend API only (no localStorage)
 */

import { classifyBasemapUrl } from "maps_maplibre/utils/basemap_url"

// Route fallback matches Map v1's blue; track color matches the backend
// Tracks::GeojsonSerializer::DEFAULT_COLOR, keep them in sync.
export const LAYER_COLOR_DEFAULTS = {
  routeColor: "#0000ff",
  trackColor: "#6366F1",
}

// hiddenTileCategories / disabledPoiGroups deliberately have no defaults:
// they enter the cache only via backend sync or an explicit set, so an
// early save can't wipe the stored values with empty arrays.
const DEFAULT_SETTINGS = {
  mapStyle: "light",
  vectorTilesUrl: null,
  ...LAYER_COLOR_DEFAULTS,
  customTheme: {
    base: "noir",
    tokens: {
      bg: "#000000",
      water: "#0A0A0A",
      parks: "#111111",
      buildings: "#141414",
      railway: "#808080",
      boundaries: "#4D4D4D",
      road_motorway: "#FFFFFF",
      road_primary: "#E0E0E0",
      road_secondary: "#B0B0B0",
      road_tertiary: "#808080",
      road_residential: "#505050",
      road_default: "#808080",
    },
  },
  enabledMapLayers: ["Heatmap", "Tracks"],
  routeOpacity: 0.6,
  fogOfWarRadius: 50,
  fogOfWarThreshold: 50,
  fogOfWarMode: "points",
  metersBetweenRoutes: 500,
  minutesBetweenRoutes: 30,
  pointsRenderingMode: "raw",
  speedColoredRoutes: false,
  speedColorScale: "0:#00ff00|15:#00ffff|30:#ff00ff|50:#ffff00|100:#ff3300",
  globeProjection: false,
  minMinutesSpentInCity: 60,
  maxGapMinutesInCity: 120,
  gpsFilteringEnabled: true,
  pointDraggingEnabled: false,
  pointsTiledRendering: false,
  enabledTransportationModes: [
    "unknown",
    "stationary",
    "walking",
    "running",
    "cycling",
    "driving",
    "bus",
    "train",
    "flying",
    "boat",
    "motorcycle",
  ],
}

const LAYER_NAME_MAP = {
  Points: "pointsVisible",
  Routes: "routesVisible",
  Heatmap: "heatmapEnabled",
  Hexagons: "hexagonsEnabled",
  Visits: "visitsEnabled",
  Photos: "photosEnabled",
  Areas: "areasEnabled",
  Tracks: "tracksEnabled",
  Flights: "flightsEnabled",
  "Fog of War": "fogEnabled",
  "Scratch map": "scratchEnabled",
  "Family Members": "familyEnabled",
  Places: "placesEnabled",
  Anomalies: "anomaliesEnabled",
}

const BACKEND_SETTINGS_MAP = {
  mapStyle: "maps_maplibre_style",
  customTheme: "maps_maplibre_custom_theme",
  vectorTilesUrl: "maps_maplibre_tiles_url",
  routeColor: "route_color",
  trackColor: "track_color",
  enabledMapLayers: "enabled_map_layers",
  routeOpacity: "route_opacity",
  fogOfWarRadius: "fog_of_war_meters",
  fogOfWarThreshold: "fog_of_war_threshold",
  fogOfWarMode: "fog_of_war_mode",
  metersBetweenRoutes: "meters_between_routes",
  minutesBetweenRoutes: "minutes_between_routes",
  pointsRenderingMode: "points_rendering_mode",
  speedColoredRoutes: "speed_colored_routes",
  speedColorScale: "speed_color_scale",
  globeProjection: "globe_projection",
  minMinutesSpentInCity: "min_minutes_spent_in_city",
  maxGapMinutesInCity: "max_gap_minutes_in_city",
  gpsFilteringEnabled: "gps_filtering_enabled",
  pointDraggingEnabled: "point_dragging_enabled",
  pointsTiledRendering: "points_tiled_rendering",
  enabledTransportationModes: "enabled_transportation_modes",
  distance_unit: "distance_unit",
  liveMapEnabled: "live_map_enabled",
}

// Layers that can only be drawn from the full point set. With tiles requested,
// routes ride the tracks tile source, fog reads the points tile source, and
// heatmap reads the tiled source — only Scratch map still needs everything.
export function bulkPointsRequired(settings = {}) {
  const tiledRequested = settings.pointsTiledRendering === true

  return (
    Boolean(settings.routesVisible !== false && !tiledRequested) ||
    Boolean(settings.heatmapEnabled && !tiledRequested) ||
    Boolean(
      settings.fogEnabled &&
        settings.fogOfWarMode !== "hexagons" &&
        !tiledRequested,
    ) ||
    Boolean(settings.scratchEnabled)
  )
}

// Tiles only save anything when nothing else already needs the full set
export function tiledPointsActive(settings = {}) {
  return settings.pointsTiledRendering === true && !bulkPointsRequired(settings)
}

// The renderer each tiled-aware layer must use for the CURRENT settings.
// Layers read tiledPointsActive once at construction; flipping the beta
// toggle (or the fog mode) mid-session re-derives everything through this
// single truth table so no layer is left on the wrong renderer.
export function tiledLayerModes(settings = {}) {
  const tiled = tiledPointsActive(settings)
  const routesOn = settings.routesVisible !== false
  const tracksOn = settings.tracksEnabled === true
  const fogTiled = tiled && (settings.fogOfWarMode || "points") !== "hexagons"

  return {
    tiled,
    tracksMvt: {
      tracksEnabled: tiled && tracksOn,
      routesVisible: tiled && routesOn,
    },
    classicRoutes: routesOn && !tiled,
    classicTracks: tracksOn && !tiled,
    anomaliesTiled: tiled,
    fogTiled,
    pointsSourceKeepAlive: fogTiled && Boolean(settings.fogEnabled),
  }
}

export class SettingsManager {
  static apiKey = null
  static cachedSettings = null
  static saveQueue = Promise.resolve()

  /**
   * Initialize settings manager with API key
   * @param {string} apiKey - User's API key for backend requests
   */
  static initialize(apiKey) {
    SettingsManager.apiKey = apiKey
    SettingsManager.cachedSettings = null
  }

  /**
   * Get all settings from cache or defaults
   * Converts enabled_map_layers array to individual boolean flags
   * @returns {Object} Settings object
   */
  static getSettings() {
    if (SettingsManager.cachedSettings) {
      return { ...SettingsManager.cachedSettings }
    }

    const expandedSettings =
      SettingsManager._expandLayerSettings(DEFAULT_SETTINGS)
    SettingsManager.cachedSettings = expandedSettings

    return { ...expandedSettings }
  }

  /**
   * Convert enabled_map_layers array to individual boolean flags
   * @param {Object} settings - Settings with enabledMapLayers array
   * @returns {Object} Settings with individual layer booleans
   */
  static _expandLayerSettings(settings) {
    const enabledLayers = settings.enabledMapLayers || []

    Object.entries(LAYER_NAME_MAP).forEach(([layerName, settingKey]) => {
      settings[settingKey] = enabledLayers.includes(layerName)
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

  static _parseIntOr(value, fallback) {
    const parsed = parseInt(value, 10)
    return Number.isNaN(parsed) ? fallback : parsed
  }

  static _parseFloatOr(value, fallback) {
    const parsed = parseFloat(value)
    return Number.isNaN(parsed) ? fallback : parsed
  }

  /**
   * Load settings from backend API
   * @returns {Promise<Object>} Settings object from backend
   */
  static async loadFromBackend() {
    if (!SettingsManager.apiKey) {
      console.warn("[Settings] API key not set, cannot load from backend")
      return null
    }

    try {
      const response = await fetch("/api/v1/settings", {
        headers: {
          Authorization: `Bearer ${SettingsManager.apiKey}`,
          "Content-Type": "application/json",
        },
      })

      if (!response.ok) {
        throw new Error(`Failed to load settings: ${response.status}`)
      }

      const data = await response.json()
      const backendSettings = data.settings

      const frontendSettings = {}
      Object.entries(BACKEND_SETTINGS_MAP).forEach(
        ([frontendKey, backendKey]) => {
          if (backendKey in backendSettings) {
            let value = backendSettings[backendKey]

            if (frontendKey === "routeOpacity") {
              value = SettingsManager._parseFloatOr(
                value,
                DEFAULT_SETTINGS.routeOpacity,
              )
            } else if (frontendKey === "fogOfWarRadius") {
              value = SettingsManager._parseIntOr(
                value,
                DEFAULT_SETTINGS.fogOfWarRadius,
              )
            } else if (frontendKey === "fogOfWarThreshold") {
              value = SettingsManager._parseIntOr(
                value,
                DEFAULT_SETTINGS.fogOfWarThreshold,
              )
            } else if (frontendKey === "metersBetweenRoutes") {
              value = SettingsManager._parseIntOr(
                value,
                DEFAULT_SETTINGS.metersBetweenRoutes,
              )
            } else if (frontendKey === "minutesBetweenRoutes") {
              value = SettingsManager._parseIntOr(
                value,
                DEFAULT_SETTINGS.minutesBetweenRoutes,
              )
            } else if (frontendKey === "minMinutesSpentInCity") {
              value = SettingsManager._parseIntOr(
                value,
                DEFAULT_SETTINGS.minMinutesSpentInCity,
              )
            } else if (frontendKey === "maxGapMinutesInCity") {
              value = SettingsManager._parseIntOr(
                value,
                DEFAULT_SETTINGS.maxGapMinutesInCity,
              )
            } else if (frontendKey === "gpsFilteringEnabled") {
              value = value === true || value === "true"
            } else if (frontendKey === "pointDraggingEnabled") {
              value = value === true || value === "true"
            } else if (frontendKey === "pointsTiledRendering") {
              value = value === true || value === "true"
            } else if (frontendKey === "speedColoredRoutes") {
              value = value === true || value === "true"
            } else if (frontendKey === "globeProjection") {
              value = value === true || value === "true"
            } else if (frontendKey === "liveMapEnabled") {
              value = value === true || value === "true"
            }

            frontendSettings[frontendKey] = value
          }
        },
      )

      const mergedSettings = { ...DEFAULT_SETTINGS, ...frontendSettings }

      if (backendSettings.enabled_map_layers) {
        mergedSettings.enabledMapLayers = backendSettings.enabled_map_layers
      }

      // Extract map customization from nested maps settings
      if (backendSettings.maps?.hidden_tile_categories) {
        mergedSettings.hiddenTileCategories =
          backendSettings.maps.hidden_tile_categories
      }
      if (backendSettings.maps?.disabled_poi_groups) {
        mergedSettings.disabledPoiGroups =
          backendSettings.maps.disabled_poi_groups
      }

      const expandedSettings =
        SettingsManager._expandLayerSettings(mergedSettings)

      SettingsManager.cachedSettings = expandedSettings

      return expandedSettings
    } catch (error) {
      console.error("[Settings] Failed to load from backend:", error)
      return null
    }
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

    try {
      const enabledMapLayers = SettingsManager._collapseLayerSettings(settings)

      const backendSettings = {}
      Object.entries(BACKEND_SETTINGS_MAP).forEach(
        ([frontendKey, backendKey]) => {
          if (frontendKey === "enabledMapLayers") {
            backendSettings[backendKey] = enabledMapLayers
          } else if (frontendKey in settings) {
            let value = settings[frontendKey]

            if (frontendKey === "routeOpacity") {
              value = parseFloat(value).toString()
            } else if (
              frontendKey === "fogOfWarRadius" ||
              frontendKey === "fogOfWarThreshold" ||
              frontendKey === "metersBetweenRoutes" ||
              frontendKey === "minutesBetweenRoutes" ||
              frontendKey === "minMinutesSpentInCity" ||
              frontendKey === "maxGapMinutesInCity"
            ) {
              value = parseInt(value, 10).toString()
            } else if (frontendKey === "speedColoredRoutes") {
              value = Boolean(value)
            } else if (frontendKey === "globeProjection") {
              value = Boolean(value)
            } else if (frontendKey === "liveMapEnabled") {
              value = Boolean(value)
            } else if (frontendKey === "pointDraggingEnabled") {
              value = Boolean(value)
            } else if (frontendKey === "pointsTiledRendering") {
              value = Boolean(value)
            }

            backendSettings[backendKey] = value
          }
        },
      )

      // distance_unit, tile categories, and POI groups live inside the
      // nested `maps` hash on the backend, the API merges it so the V1
      // keys managed by the settings page survive.
      // biome-ignore lint/performance/noDelete: key must be absent, not undefined
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
        headers: {
          Authorization: `Bearer ${SettingsManager.apiKey}`,
          "Content-Type": "application/json",
        },
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

    const previousSave = SettingsManager.saveQueue.catch(() => null)
    const save = previousSave.then(() =>
      SettingsManager.saveToBackend(settings),
    )
    SettingsManager.saveQueue = save

    return await save
  }

  /**
   * Reset to defaults
   */
  static async resetToDefaults() {
    try {
      SettingsManager.cachedSettings = null

      if (SettingsManager.apiKey) {
        await SettingsManager.saveToBackend(DEFAULT_SETTINGS)
      }
    } catch (error) {
      console.error("Failed to reset settings:", error)
    }
  }

  /**
   * Sync settings: load from backend
   * Call this on app initialization
   * @returns {Promise<Object>} Settings from backend
   */
  static async sync() {
    const backendSettings = await SettingsManager.loadFromBackend()
    if (backendSettings) {
      return backendSettings
    }
    return SettingsManager.getSettings()
  }
}
