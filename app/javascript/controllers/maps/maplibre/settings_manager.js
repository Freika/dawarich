import { SettingsManager } from 'maps_maplibre/utils/settings_manager'
import { getMapStyle } from 'maps_maplibre/utils/style_manager'
import { Toast } from 'maps_maplibre/components/toast'

/**
 * Handles all settings-related operations for Maps V2
 * Including toggles, advanced settings, and UI synchronization
 */
export class SettingsController {
  constructor(controller) {
    this.controller = controller
    this.settings = controller.settings
  }

  // Lazy getters for properties that may not be initialized yet
  get map() {
    return this.controller.map
  }

  get layerManager() {
    return this.controller.layerManager
  }

  /**
   * Load settings (sync from backend and localStorage)
   */
  async loadSettings() {
    this.settings = await SettingsManager.sync()
    this.controller.settings = this.settings
    console.log('[Maps V2] Settings loaded:', this.settings)
    return this.settings
  }

  /**
   * Sync UI controls with loaded settings
   */
  syncToggleStates() {
    const controller = this.controller

    // Sync layer toggles
    const toggleMap = {
      pointsToggle: 'pointsVisible',
      routesToggle: 'routesVisible',
      heatmapToggle: 'heatmapEnabled',
      visitsToggle: 'visitsEnabled',
      photosToggle: 'photosEnabled',
      areasToggle: 'areasEnabled',
      placesToggle: 'placesEnabled',
      fogToggle: 'fogEnabled',
      scratchToggle: 'scratchEnabled',
      speedColoredToggle: 'speedColoredRoutesEnabled'
    }

    Object.entries(toggleMap).forEach(([targetName, settingKey]) => {
      const target = `${targetName}Target`
      if (controller[target]) {
        controller[target].checked = this.settings[settingKey]
      }
    })

    // Show/hide visits search based on initial toggle state
    if (controller.hasVisitsToggleTarget && controller.hasVisitsSearchTarget) {
      controller.visitsSearchTarget.style.display = controller.visitsToggleTarget.checked ? 'block' : 'none'
    }

    // Show/hide places filters based on initial toggle state
    if (controller.hasPlacesToggleTarget && controller.hasPlacesFiltersTarget) {
      controller.placesFiltersTarget.style.display = controller.placesToggleTarget.checked ? 'block' : 'none'
    }

    // Sync route opacity slider
    if (controller.hasRouteOpacityRangeTarget) {
      controller.routeOpacityRangeTarget.value = (this.settings.routeOpacity || 1.0) * 100
    }

    // Sync map style dropdown
    const mapStyleSelect = controller.element.querySelector('select[name="mapStyle"]')
    if (mapStyleSelect) {
      mapStyleSelect.value = this.settings.mapStyle || 'light'
    }

    // Sync fog of war settings
    const fogRadiusInput = controller.element.querySelector('input[name="fogOfWarRadius"]')
    if (fogRadiusInput) {
      fogRadiusInput.value = this.settings.fogOfWarRadius || 1000
      if (controller.hasFogRadiusValueTarget) {
        controller.fogRadiusValueTarget.textContent = `${fogRadiusInput.value}m`
      }
    }

    const fogThresholdInput = controller.element.querySelector('input[name="fogOfWarThreshold"]')
    if (fogThresholdInput) {
      fogThresholdInput.value = this.settings.fogOfWarThreshold || 1
      if (controller.hasFogThresholdValueTarget) {
        controller.fogThresholdValueTarget.textContent = fogThresholdInput.value
      }
    }

    // Sync route generation settings
    const metersBetweenInput = controller.element.querySelector('input[name="metersBetweenRoutes"]')
    if (metersBetweenInput) {
      metersBetweenInput.value = this.settings.metersBetweenRoutes || 500
      if (controller.hasMetersBetweenValueTarget) {
        controller.metersBetweenValueTarget.textContent = `${metersBetweenInput.value}m`
      }
    }

    const minutesBetweenInput = controller.element.querySelector('input[name="minutesBetweenRoutes"]')
    if (minutesBetweenInput) {
      minutesBetweenInput.value = this.settings.minutesBetweenRoutes || 60
      if (controller.hasMinutesBetweenValueTarget) {
        controller.minutesBetweenValueTarget.textContent = `${minutesBetweenInput.value}min`
      }
    }

    // Sync speed-colored routes settings
    if (controller.hasSpeedColorScaleInputTarget) {
      const colorScale = this.settings.speedColorScale || '0:#00ff00|15:#00ffff|30:#ff00ff|50:#ffff00|100:#ff3300'
      controller.speedColorScaleInputTarget.value = colorScale
    }
    if (controller.hasSpeedColorScaleContainerTarget && controller.hasSpeedColoredToggleTarget) {
      const isEnabled = controller.speedColoredToggleTarget.checked
      controller.speedColorScaleContainerTarget.classList.toggle('hidden', !isEnabled)
    }

    // Sync points rendering mode radio buttons
    const pointsRenderingRadios = controller.element.querySelectorAll('input[name="pointsRenderingMode"]')
    pointsRenderingRadios.forEach(radio => {
      radio.checked = radio.value === (this.settings.pointsRenderingMode || 'raw')
    })

    // Sync speed-colored routes toggle
    const speedColoredRoutesToggle = controller.element.querySelector('input[name="speedColoredRoutes"]')
    if (speedColoredRoutesToggle) {
      speedColoredRoutesToggle.checked = this.settings.speedColoredRoutes || false
    }

    console.log('[Maps V2] UI controls synced with settings')
  }

  /**
   * Update map style from settings
   */
  async updateMapStyle(event) {
    const styleName = event.target.value
    SettingsManager.updateSetting('mapStyle', styleName)

    const style = await getMapStyle(styleName)

    // Clear layer references
    this.layerManager.clearLayerReferences()

    this.map.setStyle(style)

    // Reload layers after style change
    this.map.once('style.load', () => {
      console.log('Style loaded, reloading map data')
      this.controller.loadMapData()
    })
  }

  /**
   * Reset settings to defaults
   */
  resetSettings() {
    if (confirm('Reset all settings to defaults? This will reload the page.')) {
      SettingsManager.resetToDefaults()
      window.location.reload()
    }
  }

  /**
   * Update route opacity in real-time
   */
  updateRouteOpacity(event) {
    const opacity = parseInt(event.target.value) / 100

    const routesLayer = this.layerManager.getLayer('routes')
    if (routesLayer && this.map.getLayer('routes')) {
      this.map.setPaintProperty('routes', 'line-opacity', opacity)
    }

    SettingsManager.updateSetting('routeOpacity', opacity)
  }

  /**
   * Update advanced settings from form submission
   */
  async updateAdvancedSettings(event) {
    event.preventDefault()

    const formData = new FormData(event.target)
    const settings = {
      routeOpacity: parseFloat(formData.get('routeOpacity')) / 100,
      fogOfWarRadius: parseInt(formData.get('fogOfWarRadius')),
      fogOfWarThreshold: parseInt(formData.get('fogOfWarThreshold')),
      metersBetweenRoutes: parseInt(formData.get('metersBetweenRoutes')),
      minutesBetweenRoutes: parseInt(formData.get('minutesBetweenRoutes')),
      pointsRenderingMode: formData.get('pointsRenderingMode'),
      speedColoredRoutes: formData.get('speedColoredRoutes') === 'on'
    }

    // Apply settings to current map
    await this.applySettingsToMap(settings)

    // Save to backend and localStorage
    for (const [key, value] of Object.entries(settings)) {
      await SettingsManager.updateSetting(key, value)
    }

    Toast.success('Settings updated successfully')
  }

  /**
   * Apply settings to map without reload
   */
  async applySettingsToMap(settings) {
    // Update route opacity
    if (settings.routeOpacity !== undefined) {
      const routesLayer = this.layerManager.getLayer('routes')
      if (routesLayer && this.map.getLayer('routes')) {
        this.map.setPaintProperty('routes', 'line-opacity', settings.routeOpacity)
      }
    }

    // Update fog of war settings
    if (settings.fogOfWarRadius !== undefined || settings.fogOfWarThreshold !== undefined) {
      const fogLayer = this.layerManager.getLayer('fog')
      if (fogLayer) {
        if (settings.fogOfWarRadius) {
          fogLayer.clearRadius = settings.fogOfWarRadius
        }
        // Redraw fog layer
        if (fogLayer.visible) {
          await fogLayer.update(fogLayer.data)
        }
      }
    }

    // For settings that require data reload
    if (settings.pointsRenderingMode || settings.speedColoredRoutes !== undefined) {
      Toast.info('Reloading map data with new settings...')
      await this.controller.loadMapData()
    }
  }

  // Display value update methods
  updateFogRadiusDisplay(event) {
    if (this.controller.hasFogRadiusValueTarget) {
      this.controller.fogRadiusValueTarget.textContent = `${event.target.value}m`
    }
  }

  updateFogThresholdDisplay(event) {
    if (this.controller.hasFogThresholdValueTarget) {
      this.controller.fogThresholdValueTarget.textContent = event.target.value
    }
  }

  updateMetersBetweenDisplay(event) {
    if (this.controller.hasMetersBetweenValueTarget) {
      this.controller.metersBetweenValueTarget.textContent = `${event.target.value}m`
    }
  }

  updateMinutesBetweenDisplay(event) {
    if (this.controller.hasMinutesBetweenValueTarget) {
      this.controller.minutesBetweenValueTarget.textContent = `${event.target.value}min`
    }
  }
}
