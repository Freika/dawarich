/**
 * Settings manager for persisting user preferences
 * Loads settings from backend API only (no localStorage)
 */

const DEFAULT_SETTINGS = {
  mapStyle: "light",
  enabledMapLayers: ["Points", "Routes"],
  routeOpacity: 0.6,
  fogOfWarRadius: 100,
  fogOfWarThreshold: 1,
  metersBetweenRoutes: 500,
  minutesBetweenRoutes: 60,
  pointsRenderingMode: "raw",
  speedColoredRoutes: false,
  speedColorScale: "0:#00ff00|15:#00ffff|30:#ff00ff|50:#ffff00|100:#ff3300",
  globeProjection: false,
  minMinutesSpentInCity: 60,
  maxGapMinutesInCity: 120,
  transportationExpertMode: false,
  transportationThresholds: {
    walkingMaxSpeed: 7,
    cyclingMaxSpeed: 45,
    drivingMaxSpeed: 220,
    flyingMinSpeed: 150,
  },
  transportationExpertThresholds: {
    stationaryMaxSpeed: 1,
    runningVsCyclingAccel: 0.25,
    cyclingVsDrivingAccel: 0.4,
    trainMinSpeed: 80,
    minSegmentDuration: 60,
    timeGapThreshold: 180,
    minFlightDistanceKm: 100,
  },
}

const LAYER_NAME_MAP = {
  Points: "pointsVisible",
  Routes: "routesVisible",
  Heatmap: "heatmapEnabled",
  Visits: "visitsEnabled",
  Photos: "photosEnabled",
  Areas: "areasEnabled",
  Tracks: "tracksEnabled",
  "Fog of War": "fogEnabled",
  "Scratch map": "scratchEnabled",
}

const BACKEND_SETTINGS_MAP = {
  mapStyle: "maps_maplibre_style",
  enabledMapLayers: "enabled_map_layers",
  routeOpacity: "route_opacity",
  fogOfWarRadius: "fog_of_war_meters",
  fogOfWarThreshold: "fog_of_war_threshold",
  metersBetweenRoutes: "meters_between_routes",
  minutesBetweenRoutes: "minutes_between_routes",
  pointsRenderingMode: "points_rendering_mode",
  speedColoredRoutes: "speed_colored_routes",
  speedColorScale: "speed_color_scale",
  globeProjection: "globe_projection",
  transportationExpertMode: "transportation_expert_mode",
  transportationThresholds: "transportation_thresholds",
  transportationExpertThresholds: "transportation_expert_thresholds",
  distance_unit: "distance_unit",
  liveMapEnabled: "live_map_enabled",
}

const TRANSPORTATION_THRESHOLD_MAP = {
  walkingMaxSpeed: "walking_max_speed",
  cyclingMaxSpeed: "cycling_max_speed",
  drivingMaxSpeed: "driving_max_speed",
  flyingMinSpeed: "flying_min_speed",
}

const TRANSPORTATION_EXPERT_THRESHOLD_MAP = {
  stationaryMaxSpeed: "stationary_max_speed",
  runningVsCyclingAccel: "running_vs_cycling_accel",
  cyclingVsDrivingAccel: "cycling_vs_driving_accel",
  trainMinSpeed: "train_min_speed",
  minSegmentDuration: "min_segment_duration",
  timeGapThreshold: "time_gap_threshold",
  minFlightDistanceKm: "min_flight_distance_km",
}

export class SettingsManager {
  static apiKey = null
  static cachedSettings = null

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

  /**
   * Convert transportation thresholds between frontend and backend formats
   * @param {Object} thresholds - Threshold object to convert
   * @param {Object} keyMap - Mapping between frontend camelCase and backend snake_case keys
   * @param {boolean} toFrontend - If true, convert from backend to frontend; otherwise, convert to backend
   * @returns {Object} Converted threshold object
   */
  static _convertTransportationThresholds(
    thresholds,
    keyMap,
    toFrontend = false,
  ) {
    if (!thresholds) return null

    const converted = {}
    if (toFrontend) {
      Object.entries(keyMap).forEach(([frontendKey, backendKey]) => {
        if (backendKey in thresholds) {
          converted[frontendKey] = parseFloat(thresholds[backendKey])
        }
      })
    } else {
      Object.entries(keyMap).forEach(([frontendKey, backendKey]) => {
        if (frontendKey in thresholds) {
          converted[backendKey] = thresholds[frontendKey]
        }
      })
    }
    return converted
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
            } else if (frontendKey === "speedColoredRoutes") {
              value = value === true || value === "true"
            } else if (frontendKey === "globeProjection") {
              value = value === true || value === "true"
            } else if (frontendKey === "transportationExpertMode") {
              value = value === true || value === "true"
            } else if (frontendKey === "liveMapEnabled") {
              value = value === true || value === "true"
            } else if (frontendKey === "transportationThresholds" && value) {
              value = SettingsManager._convertTransportationThresholds(
                value,
                TRANSPORTATION_THRESHOLD_MAP,
                true,
              )
            } else if (
              frontendKey === "transportationExpertThresholds" &&
              value
            ) {
              value = SettingsManager._convertTransportationThresholds(
                value,
                TRANSPORTATION_EXPERT_THRESHOLD_MAP,
                true,
              )
            }

            frontendSettings[frontendKey] = value
          }
        },
      )

      const mergedSettings = { ...DEFAULT_SETTINGS, ...frontendSettings }

      if (backendSettings.enabled_map_layers) {
        mergedSettings.enabledMapLayers = backendSettings.enabled_map_layers
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
              frontendKey === "minutesBetweenRoutes"
            ) {
              value = parseInt(value, 10).toString()
            } else if (frontendKey === "speedColoredRoutes") {
              value = Boolean(value)
            } else if (frontendKey === "globeProjection") {
              value = Boolean(value)
            } else if (frontendKey === "transportationExpertMode") {
              value = Boolean(value)
            } else if (frontendKey === "liveMapEnabled") {
              value = Boolean(value)
            } else if (frontendKey === "transportationThresholds" && value) {
              value = SettingsManager._convertTransportationThresholds(
                value,
                TRANSPORTATION_THRESHOLD_MAP,
                false,
              )
            } else if (
              frontendKey === "transportationExpertThresholds" &&
              value
            ) {
              value = SettingsManager._convertTransportationThresholds(
                value,
                TRANSPORTATION_EXPERT_THRESHOLD_MAP,
                false,
              )
            }

            backendSettings[backendKey] = value
          }
        },
      )

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

  /**
   * Update a specific setting and save to backend
   * @param {string} key - Setting key
   * @param {*} value - New value
   * @returns {Promise<Object|null>} API response data
   */
  static async updateSetting(key, value) {
    const settings = SettingsManager.getSettings()
    settings[key] = value

    const isLayerSetting = Object.values(LAYER_NAME_MAP).includes(key)
    if (isLayerSetting) {
      settings.enabledMapLayers =
        SettingsManager._collapseLayerSettings(settings)
    }

    SettingsManager.updateCache(settings)

    return await SettingsManager.saveToBackend(settings)
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
