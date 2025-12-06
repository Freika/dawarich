/**
 * Settings manager for persisting user preferences
 * Supports both localStorage (fallback) and backend API (primary)
 */

const STORAGE_KEY = 'dawarich-maps-maplibre-settings'

const DEFAULT_SETTINGS = {
  mapStyle: 'light',
  enabledMapLayers: ['Points', 'Routes'], // Compatible with v1 map
  // Advanced settings
  routeOpacity: 1.0,
  fogOfWarRadius: 1000,
  fogOfWarThreshold: 1,
  metersBetweenRoutes: 500,
  minutesBetweenRoutes: 60,
  pointsRenderingMode: 'raw',
  speedColoredRoutes: false
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
  enabledMapLayers: 'enabled_map_layers'
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
   * Get all settings (localStorage first, then merge with defaults)
   * Converts enabled_map_layers array to individual boolean flags
   * Uses cached settings if available to avoid race conditions
   * @returns {Object} Settings object
   */
  static getSettings() {
    // Return cached settings if available
    if (this.cachedSettings) {
      return { ...this.cachedSettings }
    }

    try {
      const stored = localStorage.getItem(STORAGE_KEY)
      const settings = stored ? { ...DEFAULT_SETTINGS, ...JSON.parse(stored) } : DEFAULT_SETTINGS

      // Convert enabled_map_layers array to individual boolean flags
      const expandedSettings = this._expandLayerSettings(settings)

      // Cache the settings
      this.cachedSettings = expandedSettings

      return { ...expandedSettings }
    } catch (error) {
      console.error('Failed to load settings:', error)
      return DEFAULT_SETTINGS
    }
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
          frontendSettings[frontendKey] = backendSettings[backendKey]
        }
      })

      // Merge with defaults, but prioritize backend's enabled_map_layers completely
      const mergedSettings = { ...DEFAULT_SETTINGS, ...frontendSettings }

      // If backend has enabled_map_layers, use it as-is (don't merge with defaults)
      if (backendSettings.enabled_map_layers) {
        mergedSettings.enabledMapLayers = backendSettings.enabled_map_layers
      }

      // Convert enabled_map_layers array to individual boolean flags
      const expandedSettings = this._expandLayerSettings(mergedSettings)

      // Save to localStorage and cache
      this.saveToLocalStorage(expandedSettings)

      return expandedSettings
    } catch (error) {
      console.error('[Settings] Failed to load from backend:', error)
      return null
    }
  }

  /**
   * Save all settings to localStorage and update cache
   * @param {Object} settings - Settings object
   */
  static saveToLocalStorage(settings) {
    try {
      // Update cache first
      this.cachedSettings = { ...settings }
      // Then save to localStorage
      localStorage.setItem(STORAGE_KEY, JSON.stringify(settings))
    } catch (error) {
      console.error('Failed to save settings to localStorage:', error)
    }
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
          backendSettings[backendKey] = settings[frontendKey]
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

      console.log('[Settings] Saved to backend successfully:', backendSettings)
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
   * Update a specific setting (saves to both localStorage and backend)
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

    // Save to localStorage immediately
    this.saveToLocalStorage(settings)

    // Save to backend (non-blocking)
    this.saveToBackend(settings).catch(error => {
      console.warn('[Settings] Backend save failed, but localStorage updated:', error)
    })
  }

  /**
   * Reset to defaults
   */
  static resetToDefaults() {
    try {
      localStorage.removeItem(STORAGE_KEY)
      this.cachedSettings = null // Clear cache

      // Also reset on backend
      if (this.apiKey) {
        this.saveToBackend(DEFAULT_SETTINGS).catch(error => {
          console.warn('[Settings] Failed to reset backend settings:', error)
        })
      }
    } catch (error) {
      console.error('Failed to reset settings:', error)
    }
  }

  /**
   * Sync settings: load from backend and merge with localStorage
   * Call this on app initialization
   * @returns {Promise<Object>} Merged settings
   */
  static async sync() {
    const backendSettings = await this.loadFromBackend()
    if (backendSettings) {
      return backendSettings
    }
    return this.getSettings()
  }
}
