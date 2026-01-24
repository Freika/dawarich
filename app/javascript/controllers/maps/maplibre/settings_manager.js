import { SettingsManager } from 'maps_maplibre/utils/settings_manager'
import { getMapStyle } from 'maps_maplibre/utils/style_manager'
import { Toast } from 'maps_maplibre/components/toast'

// Polling interval for recalculation status (5 seconds)
const RECALCULATION_POLL_INTERVAL = 5000

/**
 * Handles all settings-related operations for Maps V2
 * Including toggles, advanced settings, and UI synchronization
 */
export class SettingsController {
  constructor(controller) {
    this.controller = controller
    this.settings = controller.settings
    this.recalculationPollTimer = null
  }

  // Lazy getters for properties that may not be initialized yet
  get map() {
    return this.controller.map
  }

  get layerManager() {
    return this.controller.layerManager
  }

  /**
   * Load settings (sync from backend)
   */
  async loadSettings() {
    this.settings = await SettingsManager.sync()
    this.controller.settings = this.settings

    // Update dataLoader with new settings
    if (this.controller.dataLoader) {
      this.controller.dataLoader.updateSettings(this.settings)
    }

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
      familyToggle: 'familyEnabled',
      speedColoredToggle: 'speedColoredRoutesEnabled'
    }

    Object.entries(toggleMap).forEach(([targetName, settingKey]) => {
      const target = `${targetName}Target`
      const hasTarget = `has${targetName.charAt(0).toUpperCase()}${targetName.slice(1)}Target`
      if (controller[hasTarget]) {
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

    // Show/hide family members list based on initial toggle state
    if (controller.hasFamilyToggleTarget && controller.hasFamilyMembersListTarget && controller.familyToggleTarget) {
      controller.familyMembersListTarget.style.display = controller.familyToggleTarget.checked ? 'block' : 'none'
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

    // Sync globe projection toggle
    if (controller.hasGlobeToggleTarget) {
      controller.globeToggleTarget.checked = this.settings.globeProjection || false
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

    // Sync transportation mode settings
    this.syncTransportationSettings()
  }

  /**
   * Sync transportation mode settings with loaded values
   */
  syncTransportationSettings() {
    const controller = this.controller
    const distanceUnit = this.getDistanceUnit()
    const isMetric = distanceUnit === 'km'

    // Sync expert mode toggle
    if (controller.hasTransportationExpertToggleTarget) {
      controller.transportationExpertToggleTarget.checked = this.settings.transportationExpertMode || false
    }

    // Show/hide expert settings based on toggle state
    if (controller.hasTransportationExpertSettingsTarget) {
      const isExpertMode = this.settings.transportationExpertMode || false
      controller.transportationExpertSettingsTarget.classList.toggle('hidden', !isExpertMode)
    }

    // Update speed unit labels
    if (controller.hasSpeedUnitLabelTarget) {
      const speedUnit = isMetric ? 'km/h' : 'mph'
      controller.speedUnitLabelTargets.forEach(label => {
        label.textContent = speedUnit
      })
    }

    // Update distance unit labels
    if (controller.hasDistanceUnitLabelTarget) {
      const distUnit = isMetric ? 'km' : 'mi'
      controller.distanceUnitLabelTargets.forEach(label => {
        label.textContent = distUnit
      })
    }

    // Sync basic transportation thresholds
    const basicThresholds = this.settings.transportationThresholds || {}
    const speedUnit = isMetric ? 'km/h' : 'mph'
    const distUnit = isMetric ? 'km' : 'mi'

    const basicInputMap = {
      walkingMaxSpeed: { input: 'walkingMaxSpeedInput', value: 'walkingMaxSpeedValue' },
      cyclingMaxSpeed: { input: 'cyclingMaxSpeedInput', value: 'cyclingMaxSpeedValue' },
      drivingMaxSpeed: { input: 'drivingMaxSpeedInput', value: 'drivingMaxSpeedValue' },
      flyingMinSpeed: { input: 'flyingMinSpeedInput', value: 'flyingMinSpeedValue' }
    }

    Object.entries(basicInputMap).forEach(([settingKey, targets]) => {
      const hasInputTarget = `has${targets.input.charAt(0).toUpperCase()}${targets.input.slice(1)}Target`
      const hasValueTarget = `has${targets.value.charAt(0).toUpperCase()}${targets.value.slice(1)}Target`

      if (controller[hasInputTarget]) {
        const value = basicThresholds[settingKey]
        if (value !== undefined) {
          const displayValue = this.toDisplaySpeed(value, isMetric)
          controller[`${targets.input}Target`].value = displayValue
          if (controller[hasValueTarget]) {
            controller[`${targets.value}Target`].textContent = `${displayValue} ${speedUnit}`
          }
        }
      }
    })

    // Sync expert transportation thresholds
    const expertThresholds = this.settings.transportationExpertThresholds || {}

    // Speed thresholds (need unit conversion)
    const expertSpeedInputs = {
      stationaryMaxSpeed: { input: 'stationaryMaxSpeedInput', value: 'stationaryMaxSpeedValue' },
      trainMinSpeed: { input: 'trainMinSpeedInput', value: 'trainMinSpeedValue' }
    }

    Object.entries(expertSpeedInputs).forEach(([settingKey, targets]) => {
      const hasInputTarget = `has${targets.input.charAt(0).toUpperCase()}${targets.input.slice(1)}Target`
      const hasValueTarget = `has${targets.value.charAt(0).toUpperCase()}${targets.value.slice(1)}Target`

      if (controller[hasInputTarget]) {
        const value = expertThresholds[settingKey]
        if (value !== undefined) {
          const displayValue = this.toDisplaySpeed(value, isMetric)
          controller[`${targets.input}Target`].value = displayValue
          if (controller[hasValueTarget]) {
            controller[`${targets.value}Target`].textContent = `${displayValue} ${speedUnit}`
          }
        }
      }
    })

    // Acceleration thresholds (no unit conversion needed - always m/s²)
    const accelInputs = {
      runningVsCyclingAccel: { input: 'runningVsCyclingAccelInput', value: 'runningVsCyclingAccelValue' },
      cyclingVsDrivingAccel: { input: 'cyclingVsDrivingAccelInput', value: 'cyclingVsDrivingAccelValue' }
    }

    Object.entries(accelInputs).forEach(([settingKey, targets]) => {
      const hasInputTarget = `has${targets.input.charAt(0).toUpperCase()}${targets.input.slice(1)}Target`
      const hasValueTarget = `has${targets.value.charAt(0).toUpperCase()}${targets.value.slice(1)}Target`

      if (controller[hasInputTarget]) {
        const value = expertThresholds[settingKey]
        if (value !== undefined) {
          controller[`${targets.input}Target`].value = value
          if (controller[hasValueTarget]) {
            controller[`${targets.value}Target`].textContent = `${value} m/s²`
          }
        }
      }
    })

    // Time thresholds (no unit conversion needed - always seconds)
    const timeInputs = {
      minSegmentDuration: { input: 'minSegmentDurationInput', value: 'minSegmentDurationValue' },
      timeGapThreshold: { input: 'timeGapThresholdInput', value: 'timeGapThresholdValue' }
    }

    Object.entries(timeInputs).forEach(([settingKey, targets]) => {
      const hasInputTarget = `has${targets.input.charAt(0).toUpperCase()}${targets.input.slice(1)}Target`
      const hasValueTarget = `has${targets.value.charAt(0).toUpperCase()}${targets.value.slice(1)}Target`

      if (controller[hasInputTarget]) {
        const value = expertThresholds[settingKey]
        if (value !== undefined) {
          controller[`${targets.input}Target`].value = value
          if (controller[hasValueTarget]) {
            controller[`${targets.value}Target`].textContent = `${value} sec`
          }
        }
      }
    })

    // Distance threshold (needs unit conversion)
    if (controller.hasMinFlightDistanceInputTarget) {
      const value = expertThresholds.minFlightDistanceKm
      if (value !== undefined) {
        const displayValue = this.toDisplayDistance(value, isMetric)
        controller.minFlightDistanceInputTarget.value = displayValue
        if (controller.hasMinFlightDistanceValueTarget) {
          controller.minFlightDistanceValueTarget.textContent = `${displayValue} ${distUnit}`
        }
      }
    }

    // Check recalculation status and update UI accordingly
    this.checkRecalculationStatus()
  }

  // ===== Transportation Mode Recalculation Status =====

  /**
   * Check the transportation mode recalculation status
   */
  async checkRecalculationStatus() {
    try {
      const apiKey = document.querySelector('meta[name="api-key"]')?.content
      if (!apiKey) return

      const response = await fetch('/api/v1/settings/transportation_recalculation_status', {
        headers: {
          'Authorization': `Bearer ${apiKey}`,
          'Content-Type': 'application/json'
        }
      })

      if (!response.ok) {
        console.warn('[Settings] Failed to check recalculation status')
        return
      }

      const data = await response.json()
      this.updateRecalculationUI(data)
    } catch (error) {
      console.error('[Settings] Error checking recalculation status:', error)
    }
  }

  /**
   * Update UI based on recalculation status
   */
  updateRecalculationUI(status) {
    const controller = this.controller
    const isProcessing = status.status === 'processing'
    const isCompleted = status.status === 'completed'
    const isFailed = status.status === 'failed'

    // Update locked state
    this.setTransportationSettingsLocked(isProcessing)

    // Update status alert
    if (controller.hasTransportationRecalculationAlertTarget) {
      const alertEl = controller.transportationRecalculationAlertTarget

      // Clear existing content
      alertEl.textContent = ''

      if (isProcessing) {
        const progress = status.total_tracks > 0
          ? Math.round((status.processed_tracks / status.total_tracks) * 100)
          : 0

        const spinner = document.createElement('span')
        spinner.className = 'loading loading-spinner loading-xs'

        const text = document.createElement('span')
        text.textContent = `Recalculating transportation modes... (${status.processed_tracks || 0}/${status.total_tracks || 0} tracks, ${progress}%)`

        alertEl.appendChild(spinner)
        alertEl.appendChild(text)
        alertEl.classList.remove('hidden', 'alert-success', 'alert-error')
        alertEl.classList.add('alert-warning')
      } else if (isCompleted) {
        const text = document.createElement('span')
        text.textContent = 'Transportation mode recalculation completed!'

        alertEl.appendChild(text)
        alertEl.classList.remove('hidden', 'alert-warning', 'alert-error')
        alertEl.classList.add('alert-success')
        // Auto-hide after 5 seconds
        setTimeout(() => alertEl.classList.add('hidden'), 5000)
      } else if (isFailed) {
        const text = document.createElement('span')
        text.textContent = `Recalculation failed: ${status.error_message || 'Unknown error'}`

        alertEl.appendChild(text)
        alertEl.classList.remove('hidden', 'alert-warning', 'alert-success')
        alertEl.classList.add('alert-error')
      } else {
        alertEl.classList.add('hidden')
      }
    }

    // Start or stop polling based on status
    if (isProcessing) {
      this.startRecalculationPolling()
    } else {
      this.stopRecalculationPolling()
    }
  }

  /**
   * Set transportation settings to locked or unlocked state
   */
  setTransportationSettingsLocked(locked) {
    const controller = this.controller

    // Get all transportation threshold inputs
    const inputTargets = [
      'walkingMaxSpeedInput', 'cyclingMaxSpeedInput', 'drivingMaxSpeedInput', 'flyingMinSpeedInput',
      'stationaryMaxSpeedInput', 'trainMinSpeedInput',
      'runningVsCyclingAccelInput', 'cyclingVsDrivingAccelInput',
      'minSegmentDurationInput', 'timeGapThresholdInput', 'minFlightDistanceInput',
      'transportationExpertToggle'
    ]

    inputTargets.forEach(targetName => {
      const hasTarget = `has${targetName.charAt(0).toUpperCase()}${targetName.slice(1)}Target`
      if (controller[hasTarget]) {
        controller[`${targetName}Target`].disabled = locked
      }
    })

    // Update locked message visibility
    if (controller.hasTransportationLockedMessageTarget) {
      controller.transportationLockedMessageTarget.classList.toggle('hidden', !locked)
    }
  }

  /**
   * Start polling for recalculation status
   */
  startRecalculationPolling() {
    if (this.recalculationPollTimer) return // Already polling

    this.recalculationPollTimer = setInterval(() => {
      this.checkRecalculationStatus()
    }, RECALCULATION_POLL_INTERVAL)
  }

  /**
   * Stop polling for recalculation status
   */
  stopRecalculationPolling() {
    if (this.recalculationPollTimer) {
      clearInterval(this.recalculationPollTimer)
      this.recalculationPollTimer = null
    }
  }

  /**
   * Toggle transportation expert mode visibility
   */
  toggleTransportationExpertMode(event) {
    const isExpertMode = event.target.checked
    const controller = this.controller

    if (controller.hasTransportationExpertSettingsTarget) {
      controller.transportationExpertSettingsTarget.classList.toggle('hidden', !isExpertMode)
    }

    // Save the expert mode setting
    this.settings.transportationExpertMode = isExpertMode
    SettingsManager.updateSetting('transportationExpertMode', isExpertMode)
  }

  /**
   * Update the display value for a transportation threshold slider (real-time feedback)
   */
  updateTransportationThresholdDisplay(event) {
    const input = event.target
    const name = input.name
    const value = parseFloat(input.value)
    const controller = this.controller
    const isMetric = this.getDistanceUnit() === 'km'

    // Map input names to value target names and units
    const displayMap = {
      // Basic speed thresholds
      walkingMaxSpeed: { target: 'walkingMaxSpeedValue', unit: isMetric ? 'km/h' : 'mph' },
      cyclingMaxSpeed: { target: 'cyclingMaxSpeedValue', unit: isMetric ? 'km/h' : 'mph' },
      drivingMaxSpeed: { target: 'drivingMaxSpeedValue', unit: isMetric ? 'km/h' : 'mph' },
      flyingMinSpeed: { target: 'flyingMinSpeedValue', unit: isMetric ? 'km/h' : 'mph' },
      // Expert speed thresholds
      stationaryMaxSpeed: { target: 'stationaryMaxSpeedValue', unit: isMetric ? 'km/h' : 'mph' },
      trainMinSpeed: { target: 'trainMinSpeedValue', unit: isMetric ? 'km/h' : 'mph' },
      // Acceleration thresholds
      runningVsCyclingAccel: { target: 'runningVsCyclingAccelValue', unit: 'm/s²' },
      cyclingVsDrivingAccel: { target: 'cyclingVsDrivingAccelValue', unit: 'm/s²' },
      // Time thresholds
      minSegmentDuration: { target: 'minSegmentDurationValue', unit: 'sec' },
      timeGapThreshold: { target: 'timeGapThresholdValue', unit: 'sec' },
      // Distance threshold
      minFlightDistanceKm: { target: 'minFlightDistanceValue', unit: isMetric ? 'km' : 'mi' }
    }

    const mapping = displayMap[name]
    if (!mapping) return

    const targetName = mapping.target
    const hasTarget = `has${targetName.charAt(0).toUpperCase()}${targetName.slice(1)}Target`

    if (controller[hasTarget]) {
      controller[`${targetName}Target`].textContent = `${value} ${mapping.unit}`
    }
  }

  /**
   * Update a transportation threshold value
   */
  async updateTransportationThreshold(event) {
    const input = event.target
    const name = input.name
    const value = parseFloat(input.value)
    const isMetric = this.getDistanceUnit() === 'km'

    // Determine which threshold group this belongs to
    const basicThresholds = ['walkingMaxSpeed', 'cyclingMaxSpeed', 'drivingMaxSpeed', 'flyingMinSpeed']
    const expertSpeedThresholds = ['stationaryMaxSpeed', 'trainMinSpeed']
    const expertAccelThresholds = ['runningVsCyclingAccel', 'cyclingVsDrivingAccel']
    const expertTimeThresholds = ['minSegmentDuration', 'timeGapThreshold']
    const expertDistanceThresholds = ['minFlightDistanceKm']

    let settingKey, settingValue, settingGroup

    if (basicThresholds.includes(name)) {
      settingGroup = 'transportationThresholds'
      settingKey = name
      settingValue = this.toMetricSpeed(value, isMetric)
    } else if (expertSpeedThresholds.includes(name)) {
      settingGroup = 'transportationExpertThresholds'
      settingKey = name
      settingValue = this.toMetricSpeed(value, isMetric)
    } else if (expertAccelThresholds.includes(name)) {
      settingGroup = 'transportationExpertThresholds'
      settingKey = name
      settingValue = value // No conversion for acceleration
    } else if (expertTimeThresholds.includes(name)) {
      settingGroup = 'transportationExpertThresholds'
      settingKey = name
      settingValue = value // No conversion for time
    } else if (expertDistanceThresholds.includes(name)) {
      settingGroup = 'transportationExpertThresholds'
      settingKey = name
      settingValue = this.toMetricDistance(value, isMetric)
    } else {
      console.warn('[Settings] Unknown transportation threshold:', name)
      return
    }

    // Update the settings object
    if (!this.settings[settingGroup]) {
      this.settings[settingGroup] = {}
    }
    this.settings[settingGroup][settingKey] = settingValue

    // Save to backend
    const result = await SettingsManager.updateSetting(settingGroup, this.settings[settingGroup])

    // Check if recalculation was triggered
    if (result && result.recalculation_triggered) {
      Toast.info('Transportation threshold updated. Recalculating all tracks...')
      // Start polling for status
      this.checkRecalculationStatus()
    } else if (result && result.status === 'locked') {
      Toast.error('Cannot update: recalculation is in progress')
      // Refresh the UI to show locked state
      this.checkRecalculationStatus()
    } else {
      Toast.success('Transportation threshold updated')
    }
  }

  // ===== Unit Conversion Helpers =====

  /**
   * Get user's preferred distance unit
   * @returns {string} 'km' or 'mi'
   */
  getDistanceUnit() {
    // Try to get from settings, default to 'km'
    return this.settings?.distanceUnit || 'km'
  }

  /**
   * Convert speed from metric (km/h) to display unit
   * @param {number} kmh - Speed in km/h
   * @param {boolean} isMetric - Whether to display in metric
   * @returns {number} Speed in display unit
   */
  toDisplaySpeed(kmh, isMetric) {
    if (isMetric) return kmh
    return Math.round(kmh * 0.621371 * 10) / 10 // km/h to mph, round to 1 decimal
  }

  /**
   * Convert speed from display unit to metric (km/h)
   * @param {number} value - Speed in display unit
   * @param {boolean} isMetric - Whether value is in metric
   * @returns {number} Speed in km/h
   */
  toMetricSpeed(value, isMetric) {
    if (isMetric) return value
    return Math.round(value / 0.621371 * 10) / 10 // mph to km/h
  }

  /**
   * Convert distance from metric (km) to display unit
   * @param {number} km - Distance in km
   * @param {boolean} isMetric - Whether to display in metric
   * @returns {number} Distance in display unit
   */
  toDisplayDistance(km, isMetric) {
    if (isMetric) return km
    return Math.round(km * 0.621371 * 10) / 10 // km to mi
  }

  /**
   * Convert distance from display unit to metric (km)
   * @param {number} value - Distance in display unit
   * @param {boolean} isMetric - Whether value is in metric
   * @returns {number} Distance in km
   */
  toMetricDistance(value, isMetric) {
    if (isMetric) return value
    return Math.round(value / 0.621371 * 10) / 10 // mi to km
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
   * Toggle globe projection
   * Requires page reload to apply since projection is set at map initialization
   */
  async toggleGlobe(event) {
    const enabled = event.target.checked
    await SettingsManager.updateSetting('globeProjection', enabled)

    Toast.info('Globe view will be applied after page reload')

    // Prompt user to reload
    if (confirm('Globe view requires a page reload to take effect. Reload now?')) {
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
    const isMetric = this.getDistanceUnit() === 'km'

    const settings = {
      routeOpacity: parseFloat(formData.get('routeOpacity')) / 100,
      fogOfWarRadius: parseInt(formData.get('fogOfWarRadius')),
      fogOfWarThreshold: parseInt(formData.get('fogOfWarThreshold')),
      metersBetweenRoutes: parseInt(formData.get('metersBetweenRoutes')),
      minutesBetweenRoutes: parseInt(formData.get('minutesBetweenRoutes')),
      pointsRenderingMode: formData.get('pointsRenderingMode'),
      speedColoredRoutes: formData.get('speedColoredRoutes') === 'on'
    }

    // Collect transportation thresholds if present (convert from display units to metric)
    const basicThresholdFields = ['walkingMaxSpeed', 'cyclingMaxSpeed', 'drivingMaxSpeed', 'flyingMinSpeed']
    const transportationThresholds = {}
    let hasTransportationThresholds = false

    basicThresholdFields.forEach(field => {
      const value = formData.get(field)
      if (value !== null && value !== '') {
        transportationThresholds[field] = this.toMetricSpeed(parseFloat(value), isMetric)
        hasTransportationThresholds = true
      }
    })

    if (hasTransportationThresholds) {
      settings.transportationThresholds = transportationThresholds
    }

    // Collect expert thresholds if expert mode is on
    const expertModeValue = formData.get('transportationExpertMode')
    if (expertModeValue === 'on') {
      settings.transportationExpertMode = true

      const expertThresholds = {}
      let hasExpertThresholds = false

      // Speed thresholds
      const expertSpeedFields = ['stationaryMaxSpeed', 'trainMinSpeed']
      expertSpeedFields.forEach(field => {
        const value = formData.get(field)
        if (value !== null && value !== '') {
          expertThresholds[field] = this.toMetricSpeed(parseFloat(value), isMetric)
          hasExpertThresholds = true
        }
      })

      // Acceleration thresholds (no conversion)
      const accelFields = ['runningVsCyclingAccel', 'cyclingVsDrivingAccel']
      accelFields.forEach(field => {
        const value = formData.get(field)
        if (value !== null && value !== '') {
          expertThresholds[field] = parseFloat(value)
          hasExpertThresholds = true
        }
      })

      // Time thresholds (no conversion)
      const timeFields = ['minSegmentDuration', 'timeGapThreshold']
      timeFields.forEach(field => {
        const value = formData.get(field)
        if (value !== null && value !== '') {
          expertThresholds[field] = parseInt(value)
          hasExpertThresholds = true
        }
      })

      // Distance threshold
      const minFlightDistance = formData.get('minFlightDistanceKm')
      if (minFlightDistance !== null && minFlightDistance !== '') {
        expertThresholds.minFlightDistanceKm = this.toMetricDistance(parseFloat(minFlightDistance), isMetric)
        hasExpertThresholds = true
      }

      if (hasExpertThresholds) {
        settings.transportationExpertThresholds = expertThresholds
      }
    }

    // Apply settings to current map
    await this.applySettingsToMap(settings)

    // Save to backend
    for (const [key, value] of Object.entries(settings)) {
      await SettingsManager.updateSetting(key, value)
    }

    // Update controller settings and dataLoader
    this.controller.settings = { ...this.controller.settings, ...settings }
    if (this.controller.dataLoader) {
      this.controller.dataLoader.updateSettings(this.controller.settings)
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
        // Redraw fog layer if it has data and is visible
        if (fogLayer.visible && fogLayer.data) {
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
