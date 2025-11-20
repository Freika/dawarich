/**
 * Settings manager for persisting user preferences
 */

const STORAGE_KEY = 'dawarich-maps-v2-settings'

const DEFAULT_SETTINGS = {
  mapStyle: 'positron',
  clustering: true,
  clusterRadius: 50,
  heatmapEnabled: false,
  pointsVisible: true,
  routesVisible: true,
  visitsEnabled: false,
  photosEnabled: false,
  areasEnabled: false,
  tracksEnabled: false
}

export class SettingsManager {
  /**
   * Get all settings
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
   * Save all settings
   * @param {Object} settings - Settings object
   */
  static saveSettings(settings) {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(settings))
    } catch (error) {
      console.error('Failed to save settings:', error)
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
   * Update a specific setting
   * @param {string} key - Setting key
   * @param {*} value - New value
   */
  static updateSetting(key, value) {
    const settings = this.getSettings()
    settings[key] = value
    this.saveSettings(settings)
  }

  /**
   * Reset to defaults
   */
  static resetToDefaults() {
    try {
      localStorage.removeItem(STORAGE_KEY)
    } catch (error) {
      console.error('Failed to reset settings:', error)
    }
  }
}
