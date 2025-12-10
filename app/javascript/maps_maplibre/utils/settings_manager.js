/**
 * Settings manager for persisting user preferences
 * Loads settings from backend API only (no localStorage)
 */

const DEFAULT_SETTINGS = {
  mapStyle: 'light',
  enabledMapLayers: ['Points', 'Routes'], // Compatible with v1 map
  // Advanced settings (matching v1 naming)
  routeOpacity: 0.6,
  fogOfWarRadius: 100,
  fogOfWarThreshold: 1,
  metersBetweenRoutes: 1000,
  minutesBetweenRoutes: 60,
  pointsRenderingMode: 'raw',
  speedColoredRoutes: false,
  speedColorScale: '0:#00ff00|15:#00ffff|30:#ff00ff|50:#ffff00|100:#ff3300'
}

// Mapping between v2 layer names and v1 layer names in enabled_map_layers array
const LAYER_NAME_MAP = {
  'Points': 'pointsVisible',
  'Routes': 'routesVisible',
  'Heatmap': 'heatmapEnabled',
  'Visits': 'visitsEnabled',
  'Photos': 'photosEnabled',
  'Areas': 'areasEnabled',
  'Tracks': 'tracksEnabled',
  'Fog of War': 'fogEnabled',
  'Scratch map': 'scratchEnabled'
}

// Mapping between frontend settings and backend API keys
const BACKEND_SETTINGS_MAP = {
  mapStyle: 'maps_maplibre_style',
  enabledMapLayers: 'enabled_map_layers',
  routeOpacity: 'route_opacity',
  fogOfWarRadius: 'fog_of_war_meters',
  fogOfWarThreshold: 'fog_of_war_threshold',
  metersBetweenRoutes: 'meters_between_routes',
  minutesBetweenRoutes: 'minutes_between_routes',
  pointsRenderingMode: 'points_rendering_mode',
  speedColoredRoutes: 'speed_colored_routes',
  speedColorScale: 'speed_color_scale'
}

export class SettingsManager {
  static apiKey = null
  static cachedSettings = null

  /**
   * Initialize settings manager with API key
   * @param {string} apiKey - User's API key for backend requests
   */
  static initialize(apiKey) {
    this.apiKey = apiKey
    this.cachedSettings = null // Clear cache on initialization
  }

  /**
   * Get all settings from cache or defaults
   * Converts enabled_map_layers array to individual boolean flags
   * @returns {Object} Settings object
   */
  static getSettings() {
    // Return cached settings if available
    if (this.cachedSettings) {
      return { ...this.cachedSettings }
    }

    // Convert enabled_map_layers array to individual boolean flags
    const expandedSettings = this._expandLayerSettings(DEFAULT_SETTINGS)
    this.cachedSettings = expandedSettings

    return { ...expandedSettings }
  }

  /**
   * Convert enabled_map_layers array to individual boolean flags
   * @param {Object} settings - Settings with enabledMapLayers array
   * @returns {Object} Settings with individual layer booleans
   */
  static _expandLayerSettings(settings) {
    const enabledLayers = settings.enabledMapLayers || []

    // Set boolean flags based on array contents
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
   * Load settings from backend API
   * @returns {Promise<Object>} Settings object from backend
   */
  static async loadFromBackend() {
    if (!this.apiKey) {
      console.warn('[Settings] API key not set, cannot load from backend')
      return null
    }

    try {
      const response = await fetch('/api/v1/settings', {
        headers: {
          'Authorization': `Bearer ${this.apiKey}`,
          'Content-Type': 'application/json'
        }
      })

      if (!response.ok) {
        throw new Error(`Failed to load settings: ${response.status}`)
      }

      const data = await response.json()
      const backendSettings = data.settings

      // Convert backend settings to frontend format
      const frontendSettings = {}
      Object.entries(BACKEND_SETTINGS_MAP).forEach(([frontendKey, backendKey]) => {
        if (backendKey in backendSettings) {
          let value = backendSettings[backendKey]

          // Convert backend values to correct types
          if (frontendKey === 'routeOpacity') {
            value = parseFloat(value) || DEFAULT_SETTINGS.routeOpacity
          } else if (frontendKey === 'fogOfWarRadius') {
            value = parseInt(value) || DEFAULT_SETTINGS.fogOfWarRadius
          } else if (frontendKey === 'fogOfWarThreshold') {
            value = parseInt(value) || DEFAULT_SETTINGS.fogOfWarThreshold
          } else if (frontendKey === 'metersBetweenRoutes') {
            value = parseInt(value) || DEFAULT_SETTINGS.metersBetweenRoutes
          } else if (frontendKey === 'minutesBetweenRoutes') {
            value = parseInt(value) || DEFAULT_SETTINGS.minutesBetweenRoutes
          } else if (frontendKey === 'speedColoredRoutes') {
            value = value === true || value === 'true'
          }

          frontendSettings[frontendKey] = value
        }
      })

      // Merge with defaults
      const mergedSettings = { ...DEFAULT_SETTINGS, ...frontendSettings }

      // If backend has enabled_map_layers, use it as-is
      if (backendSettings.enabled_map_layers) {
        mergedSettings.enabledMapLayers = backendSettings.enabled_map_layers
      }

      // Convert enabled_map_layers array to individual boolean flags
      const expandedSettings = this._expandLayerSettings(mergedSettings)

      // Cache the settings
      this.cachedSettings = expandedSettings

      return expandedSettings
    } catch (error) {
      console.error('[Settings] Failed to load from backend:', error)
      return null
    }
  }

  /**
   * Update cache with new settings
   * @param {Object} settings - Settings object
   */
  static updateCache(settings) {
    this.cachedSettings = { ...settings }
  }

  /**
   * Save settings to backend API
   * @param {Object} settings - Settings to save
   * @returns {Promise<boolean>} Success status
   */
  static async saveToBackend(settings) {
    if (!this.apiKey) {
      console.warn('[Settings] API key not set, cannot save to backend')
      return false
    }

    try {
      // Convert individual layer booleans to enabled_map_layers array
      const enabledMapLayers = this._collapseLayerSettings(settings)

      // Convert frontend settings to backend format
      const backendSettings = {}
      Object.entries(BACKEND_SETTINGS_MAP).forEach(([frontendKey, backendKey]) => {
        if (frontendKey === 'enabledMapLayers') {
          // Use the collapsed array
          backendSettings[backendKey] = enabledMapLayers
        } else if (frontendKey in settings) {
          let value = settings[frontendKey]

          // Convert frontend values to backend format
          if (frontendKey === 'routeOpacity') {
            value = parseFloat(value).toString()
          } else if (frontendKey === 'fogOfWarRadius' || frontendKey === 'fogOfWarThreshold' ||
                     frontendKey === 'metersBetweenRoutes' || frontendKey === 'minutesBetweenRoutes') {
            value = parseInt(value).toString()
          } else if (frontendKey === 'speedColoredRoutes') {
            value = Boolean(value)
          }

          backendSettings[backendKey] = value
        }
      })

      const response = await fetch('/api/v1/settings', {
        method: 'PATCH',
        headers: {
          'Authorization': `Bearer ${this.apiKey}`,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({ settings: backendSettings })
      })

      if (!response.ok) {
        throw new Error(`Failed to save settings: ${response.status}`)
      }

      return true
    } catch (error) {
      console.error('[Settings] Failed to save to backend:', error)
      return false
    }
  }

  /**
   * Get a specific setting
   * @param {string} key - Setting key
   * @returns {*} Setting value
   */
  static getSetting(key) {
    return this.getSettings()[key]
  }

  /**
   * Update a specific setting and save to backend
   * @param {string} key - Setting key
   * @param {*} value - New value
   */
  static async updateSetting(key, value) {
    const settings = this.getSettings()
    settings[key] = value

    // If this is a layer visibility setting, also update the enabledMapLayers array
    // This ensures the array is in sync before backend save
    const isLayerSetting = Object.values(LAYER_NAME_MAP).includes(key)
    if (isLayerSetting) {
      settings.enabledMapLayers = this._collapseLayerSettings(settings)
    }

    // Update cache immediately
    this.updateCache(settings)

    // Save to backend
    await this.saveToBackend(settings)
  }

  /**
   * Reset to defaults
   */
  static async resetToDefaults() {
    try {
      this.cachedSettings = null // Clear cache

      // Reset on backend
      if (this.apiKey) {
        await this.saveToBackend(DEFAULT_SETTINGS)
      }
    } catch (error) {
      console.error('Failed to reset settings:', error)
    }
  }

  /**
   * Sync settings: load from backend
   * Call this on app initialization
   * @returns {Promise<Object>} Settings from backend
   */
  static async sync() {
    const backendSettings = await this.loadFromBackend()
    if (backendSettings) {
      return backendSettings
    }
    return this.getSettings()
  }
}
