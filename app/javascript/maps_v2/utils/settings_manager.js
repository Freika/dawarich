/**
 * Settings manager for persisting user preferences
 * Supports both localStorage (fallback) and backend API (primary)
 */

const STORAGE_KEY = 'dawarich-maps-v2-settings'

const DEFAULT_SETTINGS = {
  mapStyle: 'light',
  clustering: true,
  clusterRadius: 50,
  heatmapEnabled: false,
  pointsVisible: true,
  routesVisible: true,
  visitsEnabled: false,
  photosEnabled: false,
  areasEnabled: false,
  tracksEnabled: false,
  fogEnabled: false,
  scratchEnabled: false
}

// Mapping between frontend settings and backend API keys
const BACKEND_SETTINGS_MAP = {
  mapStyle: 'maps_v2_style',
  heatmapEnabled: 'maps_v2_heatmap',
  visitsEnabled: 'maps_v2_visits',
  photosEnabled: 'maps_v2_photos',
  areasEnabled: 'maps_v2_areas',
  tracksEnabled: 'maps_v2_tracks',
  fogEnabled: 'maps_v2_fog',
  scratchEnabled: 'maps_v2_scratch',
  clustering: 'maps_v2_clustering',
  clusterRadius: 'maps_v2_cluster_radius'
}

export class SettingsManager {
  static apiKey = null

  /**
   * Initialize settings manager with API key
   * @param {string} apiKey - User's API key for backend requests
   */
  static initialize(apiKey) {
    this.apiKey = apiKey
  }

  /**
   * Get all settings (localStorage first, then merge with defaults)
   * @returns {Object} Settings object
   */
  static getSettings() {
    try {
      const stored = localStorage.getItem(STORAGE_KEY)
      return stored ? { ...DEFAULT_SETTINGS, ...JSON.parse(stored) } : DEFAULT_SETTINGS
    } catch (error) {
      console.error('Failed to load settings:', error)
      return DEFAULT_SETTINGS
    }
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

      // Merge with defaults and save to localStorage
      const mergedSettings = { ...DEFAULT_SETTINGS, ...frontendSettings }
      this.saveToLocalStorage(mergedSettings)

      return mergedSettings
    } catch (error) {
      console.error('[Settings] Failed to load from backend:', error)
      return null
    }
  }

  /**
   * Save all settings to localStorage
   * @param {Object} settings - Settings object
   */
  static saveToLocalStorage(settings) {
    try {
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
      // Convert frontend settings to backend format
      const backendSettings = {}
      Object.entries(BACKEND_SETTINGS_MAP).forEach(([frontendKey, backendKey]) => {
        if (frontendKey in settings) {
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

      console.log('[Settings] Saved to backend successfully')
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
