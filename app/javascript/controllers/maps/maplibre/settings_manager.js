import { Toast } from "maps_maplibre/components/toast"
import { SettingsManager } from "maps_maplibre/utils/settings_manager"
import { getMapStyle } from "maps_maplibre/utils/style_manager"

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
    this.transportationSettingsDirty = false
    this.isTransportationSettingsLocked = false
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
      pointsToggle: "pointsVisible",
      routesToggle: "routesVisible",
      heatmapToggle: "heatmapEnabled",
      visitsToggle: "visitsEnabled",
      photosToggle: "photosEnabled",
      areasToggle: "areasEnabled",
      placesToggle: "placesEnabled",
      fogToggle: "fogEnabled",
      scratchToggle: "scratchEnabled",
      familyToggle: "familyEnabled",
      speedColoredToggle: "speedColoredRoutes",
      tracksToggle: "tracksEnabled",
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
      controller.visitsSearchTarget.style.display = controller
        .visitsToggleTarget.checked
        ? "block"
        : "none"
    }

    // Show/hide places filters based on initial toggle state
    if (controller.hasPlacesToggleTarget && controller.hasPlacesFiltersTarget) {
      controller.placesFiltersTarget.style.display = controller
        .placesToggleTarget.checked
        ? "block"
        : "none"
    }

    // Show/hide family members list based on initial toggle state
    if (
      controller.hasFamilyToggleTarget &&
      controller.hasFamilyMembersListTarget &&
      controller.familyToggleTarget
    ) {
      controller.familyMembersListTarget.style.display = controller
        .familyToggleTarget.checked
        ? "block"
        : "none"
    }

    // Sync route opacity slider
    if (controller.hasRouteOpacityRangeTarget) {
      controller.routeOpacityRangeTarget.value =
        (this.settings.routeOpacity || 1.0) * 100
    }

    // Sync map style dropdown
    const mapStyleSelect = controller.element.querySelector(
      'select[name="mapStyle"]',
    )
    if (mapStyleSelect) {
      mapStyleSelect.value = this.settings.mapStyle || "light"
    }

    // Sync globe projection toggle
    if (controller.hasGlobeToggleTarget) {
      controller.globeToggleTarget.checked =
        this.settings.globeProjection || false
    }

    // Sync fog of war settings
    const fogRadiusInput = controller.element.querySelector(
      'input[name="fogOfWarRadius"]',
    )
    if (fogRadiusInput) {
      fogRadiusInput.value = this.settings.fogOfWarRadius || 1000
      if (controller.hasFogRadiusValueTarget) {
        controller.fogRadiusValueTarget.textContent = `${fogRadiusInput.value}m`
      }
    }

    const fogThresholdInput = controller.element.querySelector(
      'input[name="fogOfWarThreshold"]',
    )
    if (fogThresholdInput) {
      fogThresholdInput.value = this.settings.fogOfWarThreshold || 1
      if (controller.hasFogThresholdValueTarget) {
        controller.fogThresholdValueTarget.textContent = fogThresholdInput.value
      }
    }

    // Sync route generation settings
    const metersBetweenInput = controller.element.querySelector(
      'input[name="metersBetweenRoutes"]',
    )
    if (metersBetweenInput) {
      metersBetweenInput.value = this.settings.metersBetweenRoutes || 500
      if (controller.hasMetersBetweenValueTarget) {
        controller.metersBetweenValueTarget.textContent = `${metersBetweenInput.value}m`
      }
    }

    const minutesBetweenInput = controller.element.querySelector(
      'input[name="minutesBetweenRoutes"]',
    )
    if (minutesBetweenInput) {
      minutesBetweenInput.value = this.settings.minutesBetweenRoutes || 60
      if (controller.hasMinutesBetweenValueTarget) {
        controller.minutesBetweenValueTarget.textContent = `${minutesBetweenInput.value}min`
      }
    }

    // Sync speed-colored routes settings
    if (controller.hasSpeedColorScaleInputTarget) {
      const colorScale =
        this.settings.speedColorScale ||
        "0:#00ff00|15:#00ffff|30:#ff00ff|50:#ffff00|100:#ff3300"
      controller.speedColorScaleInputTarget.value = colorScale
    }
    if (
      controller.hasSpeedColorScaleContainerTarget &&
      controller.hasSpeedColoredToggleTarget
    ) {
      const isEnabled = controller.speedColoredToggleTarget.checked
      controller.speedColorScaleContainerTarget.classList.toggle(
        "hidden",
        !isEnabled,
      )
    }

    // Sync points rendering mode radio buttons
    const pointsRenderingRadios = controller.element.querySelectorAll(
      'input[name="pointsRenderingMode"]',
    )
    pointsRenderingRadios.forEach((radio) => {
      radio.checked =
        radio.value === (this.settings.pointsRenderingMode || "raw")
    })

    // Sync speed-colored routes toggle
    const speedColoredRoutesToggle = controller.element.querySelector(
      'input[name="speedColoredRoutes"]',
    )
    if (speedColoredRoutesToggle) {
      speedColoredRoutesToggle.checked =
        this.settings.speedColoredRoutes || false
    }

    // Sync transportation mode settings
    this.syncTransportationSettings()
  }

  /**
   * Sync transportation mode settings with loaded values
   */
  async syncTransportationSettings() {
    const controller = this.controller
    const distanceUnit = this.getDistanceUnit()
    const isMetric = distanceUnit === "km"

    // Sync expert mode toggle
    if (controller.hasTransportationExpertToggleTarget) {
      controller.transportationExpertToggleTarget.checked =
        this.settings.transportationExpertMode || false
    }

    // Show/hide expert settings based on toggle state
    if (controller.hasTransportationExpertSettingsTarget) {
      const isExpertMode = this.settings.transportationExpertMode || false
      controller.transportationExpertSettingsTarget.classList.toggle(
        "hidden",
        !isExpertMode,
      )
    }

    // Update speed unit labels
    if (controller.hasSpeedUnitLabelTarget) {
      const speedUnit = isMetric ? "km/h" : "mph"
      controller.speedUnitLabelTargets.forEach((label) => {
        label.textContent = speedUnit
      })
    }

    // Update distance unit labels
    if (controller.hasDistanceUnitLabelTarget) {
      const distUnit = isMetric ? "km" : "mi"
      controller.distanceUnitLabelTargets.forEach((label) => {
        label.textContent = distUnit
      })
    }

    // Sync basic transportation thresholds
    const basicThresholds = this.settings.transportationThresholds || {}
    const speedUnit = isMetric ? "km/h" : "mph"
    const distUnit = isMetric ? "km" : "mi"

    const basicInputMap = {
      walkingMaxSpeed: {
        input: "walkingMaxSpeedInput",
        value: "walkingMaxSpeedValue",
      },
      cyclingMaxSpeed: {
        input: "cyclingMaxSpeedInput",
        value: "cyclingMaxSpeedValue",
      },
      drivingMaxSpeed: {
        input: "drivingMaxSpeedInput",
        value: "drivingMaxSpeedValue",
      },
      flyingMinSpeed: {
        input: "flyingMinSpeedInput",
        value: "flyingMinSpeedValue",
      },
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
            controller[`${targets.value}Target`].textContent =
              `${displayValue} ${speedUnit}`
          }
        }
      }
    })

    // Sync expert transportation thresholds
    const expertThresholds = this.settings.transportationExpertThresholds || {}

    // Speed thresholds (need unit conversion)
    const expertSpeedInputs = {
      stationaryMaxSpeed: {
        input: "stationaryMaxSpeedInput",
        value: "stationaryMaxSpeedValue",
      },
      trainMinSpeed: {
        input: "trainMinSpeedInput",
        value: "trainMinSpeedValue",
      },
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
            controller[`${targets.value}Target`].textContent =
              `${displayValue} ${speedUnit}`
          }
        }
      }
    })

    // Acceleration thresholds (no unit conversion needed - always m/s²)
    const accelInputs = {
      runningVsCyclingAccel: {
        input: "runningVsCyclingAccelInput",
        value: "runningVsCyclingAccelValue",
      },
      cyclingVsDrivingAccel: {
        input: "cyclingVsDrivingAccelInput",
        value: "cyclingVsDrivingAccelValue",
      },
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
      minSegmentDuration: {
        input: "minSegmentDurationInput",
        value: "minSegmentDurationValue",
      },
      timeGapThreshold: {
        input: "timeGapThresholdInput",
        value: "timeGapThresholdValue",
      },
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
    // This will also handle locking the form if recalculation is in progress
    await this.checkRecalculationStatus()

    // Only reset dirty state if not locked (recalculation not in progress)
    // The lock state is set by checkRecalculationStatus -> updateRecalculationUI
    if (!this.isTransportationSettingsLocked) {
      this.resetTransportationDirtyState()
    }
  }

  /**
   * Reset transportation settings dirty state
   */
  resetTransportationDirtyState() {
    this.transportationSettingsDirty = false
    this.updateTransportationApplyButton()
  }

  /**
   * Update the apply button state based on dirty flag
   */
  updateTransportationApplyButton() {
    const controller = this.controller

    if (controller.hasTransportationApplyButtonTarget) {
      controller.transportationApplyButtonTarget.disabled =
        !this.transportationSettingsDirty
    }

    if (controller.hasTransportationDirtyMessageTarget) {
      if (this.transportationSettingsDirty) {
        controller.transportationDirtyMessageTarget.textContent =
          "You have unsaved changes. Click Apply to save and recalculate."
        controller.transportationDirtyMessageTarget.classList.add(
          "text-warning",
        )
        controller.transportationDirtyMessageTarget.classList.remove(
          "text-base-content/60",
        )
      } else {
        controller.transportationDirtyMessageTarget.textContent =
          "Make changes to enable the Apply button"
        controller.transportationDirtyMessageTarget.classList.remove(
          "text-warning",
        )
        controller.transportationDirtyMessageTarget.classList.add(
          "text-base-content/60",
        )
      }
    }
  }

  /**
   * Mark transportation settings as dirty (changed but not saved)
   */
  markTransportationSettingsDirty() {
    this.transportationSettingsDirty = true
    this.updateTransportationApplyButton()
  }

  /**
   * Apply transportation settings with confirmation
   */
  async applyTransportationSettings() {
    const _controller = this.controller

    // Show confirmation dialog
    const confirmed = confirm(
      "Applying these changes will recalculate transportation modes for ALL your tracks.\n\n" +
        "This process may take some time depending on how many tracks you have, and settings will be locked until it completes.\n\n" +
        "Do you want to continue?",
    )

    if (!confirmed) return

    // Collect all threshold values from inputs
    await this.saveTransportationThresholds()
  }

  /**
   * Save all transportation thresholds to backend
   */
  async saveTransportationThresholds() {
    const controller = this.controller
    const isMetric = this.getDistanceUnit() === "km"

    // Collect basic thresholds
    const transportationThresholds = {}
    const basicInputs = [
      "walkingMaxSpeed",
      "cyclingMaxSpeed",
      "drivingMaxSpeed",
      "flyingMinSpeed",
    ]

    basicInputs.forEach((name) => {
      const targetName = `${name}InputTarget`
      const hasTarget = `has${name.charAt(0).toUpperCase()}${name.slice(1)}InputTarget`
      if (controller[hasTarget]) {
        const value = parseFloat(controller[targetName].value)
        transportationThresholds[name] = this.toMetricSpeed(value, isMetric)
      }
    })

    // Collect expert thresholds
    const transportationExpertThresholds = {}

    // Speed thresholds
    const expertSpeedInputs = ["stationaryMaxSpeed", "trainMinSpeed"]
    expertSpeedInputs.forEach((name) => {
      const targetName = `${name}InputTarget`
      const hasTarget = `has${name.charAt(0).toUpperCase()}${name.slice(1)}InputTarget`
      if (controller[hasTarget]) {
        const value = parseFloat(controller[targetName].value)
        transportationExpertThresholds[name] = this.toMetricSpeed(
          value,
          isMetric,
        )
      }
    })

    // Acceleration thresholds (no conversion)
    const accelInputs = ["runningVsCyclingAccel", "cyclingVsDrivingAccel"]
    accelInputs.forEach((name) => {
      const targetName = `${name}InputTarget`
      const hasTarget = `has${name.charAt(0).toUpperCase()}${name.slice(1)}InputTarget`
      if (controller[hasTarget]) {
        transportationExpertThresholds[name] = parseFloat(
          controller[targetName].value,
        )
      }
    })

    // Time thresholds (no conversion)
    const timeInputs = ["minSegmentDuration", "timeGapThreshold"]
    timeInputs.forEach((name) => {
      const targetName = `${name}InputTarget`
      const hasTarget = `has${name.charAt(0).toUpperCase()}${name.slice(1)}InputTarget`
      if (controller[hasTarget]) {
        transportationExpertThresholds[name] = parseInt(
          controller[targetName].value,
          10,
        )
      }
    })

    // Distance threshold
    if (controller.hasMinFlightDistanceInputTarget) {
      const value = parseFloat(controller.minFlightDistanceInputTarget.value)
      transportationExpertThresholds.minFlightDistanceKm =
        this.toMetricDistance(value, isMetric)
    }

    // Update settings object
    this.settings.transportationThresholds = transportationThresholds
    this.settings.transportationExpertThresholds =
      transportationExpertThresholds

    // Save to backend
    const result = await SettingsManager.updateSetting(
      "transportationThresholds",
      transportationThresholds,
    )
    await SettingsManager.updateSetting(
      "transportationExpertThresholds",
      transportationExpertThresholds,
    )

    // Check result and update UI
    if (result && result.status === "locked") {
      Toast.error("Cannot update: recalculation is already in progress")
      // Immediately lock the UI
      this.setTransportationSettingsLocked(true)
      // Also start polling for status updates
      this.startRecalculationPolling()
      return
    }

    if (result?.recalculation_triggered) {
      Toast.info(
        "Settings saved. Recalculating transportation modes for all tracks...",
      )
      this.resetTransportationDirtyState()
      // Immediately lock the UI since recalculation started
      this.setTransportationSettingsLocked(true)
      // Start polling for status updates
      this.startRecalculationPolling()
    } else {
      Toast.success("Transportation settings saved")
      this.resetTransportationDirtyState()
    }
  }

  // ===== Transportation Mode Recalculation Status =====

  /**
   * Check the transportation mode recalculation status
   */
  async checkRecalculationStatus() {
    try {
      const apiKey = this.controller.apiKeyValue
      if (!apiKey) {
        console.warn(
          "[Settings] No API key available for recalculation status check",
        )
        return
      }

      const response = await fetch(
        "/api/v1/settings/transportation_recalculation_status",
        {
          headers: {
            Authorization: `Bearer ${apiKey}`,
            "Content-Type": "application/json",
          },
        },
      )

      if (!response.ok) {
        console.warn(
          "[Settings] Failed to check recalculation status:",
          response.status,
        )
        return
      }

      const data = await response.json()
      this.updateRecalculationUI(data)
    } catch (error) {
      console.error("[Settings] Error checking recalculation status:", error)
    }
  }

  /**
   * Update UI based on recalculation status
   */
  updateRecalculationUI(status) {
    const controller = this.controller
    const isProcessing = status.status === "processing"
    const isCompleted = status.status === "completed"
    const isFailed = status.status === "failed"

    // Update locked state
    this.setTransportationSettingsLocked(isProcessing)

    // Update status alert
    if (controller.hasTransportationRecalculationAlertTarget) {
      const alertEl = controller.transportationRecalculationAlertTarget

      // Clear existing content
      alertEl.textContent = ""

      if (isProcessing) {
        const progress =
          status.total_tracks > 0
            ? Math.round((status.processed_tracks / status.total_tracks) * 100)
            : 0

        const processedFormatted = (
          status.processed_tracks || 0
        ).toLocaleString()
        const totalFormatted = (status.total_tracks || 0).toLocaleString()

        // Create inline container for spinner and text
        const container = document.createElement("span")
        container.className = "inline-flex items-center gap-2"

        const spinner = document.createElement("span")
        spinner.className = "loading loading-spinner loading-xs"

        const text = document.createElement("span")
        text.textContent = `Recalculating transportation modes... (${processedFormatted}/${totalFormatted} tracks, ${progress}%)`

        container.appendChild(spinner)
        container.appendChild(text)
        alertEl.appendChild(container)
        alertEl.classList.remove("hidden", "alert-success", "alert-error")
        alertEl.classList.add("alert-warning")
      } else if (isCompleted) {
        const text = document.createElement("span")
        text.textContent = "Transportation mode recalculation completed!"

        alertEl.appendChild(text)
        alertEl.classList.remove("hidden", "alert-warning", "alert-error")
        alertEl.classList.add("alert-success")
        // Auto-hide after 5 seconds
        setTimeout(() => alertEl.classList.add("hidden"), 5000)
        // Reset dirty state so apply button shows correct message
        this.resetTransportationDirtyState()
      } else if (isFailed) {
        const text = document.createElement("span")
        text.textContent = `Recalculation failed: ${status.error_message || "Unknown error"}`

        alertEl.appendChild(text)
        alertEl.classList.remove("hidden", "alert-warning", "alert-success")
        alertEl.classList.add("alert-error")
      } else {
        alertEl.classList.add("hidden")
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
    // Track the locked state
    this.isTransportationSettingsLocked = locked

    const controller = this.controller

    // Get all transportation threshold inputs
    const inputTargets = [
      "walkingMaxSpeedInput",
      "cyclingMaxSpeedInput",
      "drivingMaxSpeedInput",
      "flyingMinSpeedInput",
      "stationaryMaxSpeedInput",
      "trainMinSpeedInput",
      "runningVsCyclingAccelInput",
      "cyclingVsDrivingAccelInput",
      "minSegmentDurationInput",
      "timeGapThresholdInput",
      "minFlightDistanceInput",
      "transportationExpertToggle",
    ]

    inputTargets.forEach((targetName) => {
      const hasTarget = `has${targetName.charAt(0).toUpperCase()}${targetName.slice(1)}Target`
      if (controller[hasTarget]) {
        const element = controller[`${targetName}Target`]
        element.disabled = locked
        // Add visual styling for disabled state
        if (locked) {
          element.classList.add("opacity-50", "cursor-not-allowed")
        } else {
          element.classList.remove("opacity-50", "cursor-not-allowed")
        }
      }
    })

    // Also disable/enable the apply button
    if (controller.hasTransportationApplyButtonTarget) {
      controller.transportationApplyButtonTarget.disabled = locked
      if (locked) {
        controller.transportationApplyButtonTarget.classList.add("btn-disabled")
      } else {
        controller.transportationApplyButtonTarget.classList.remove(
          "btn-disabled",
        )
      }
    }

    // Gray out the basic and expert settings containers
    if (controller.hasTransportationBasicSettingsTarget) {
      if (locked) {
        controller.transportationBasicSettingsTarget.classList.add(
          "opacity-50",
          "pointer-events-none",
        )
      } else {
        controller.transportationBasicSettingsTarget.classList.remove(
          "opacity-50",
          "pointer-events-none",
        )
      }
    }

    if (controller.hasTransportationExpertSettingsTarget) {
      if (locked) {
        controller.transportationExpertSettingsTarget.classList.add(
          "opacity-50",
          "pointer-events-none",
        )
      } else {
        controller.transportationExpertSettingsTarget.classList.remove(
          "opacity-50",
          "pointer-events-none",
        )
      }
    }

    // Update locked message visibility
    if (controller.hasTransportationLockedMessageTarget) {
      controller.transportationLockedMessageTarget.classList.toggle(
        "hidden",
        !locked,
      )
    }

    // Update dirty message visibility (hide when locked)
    if (controller.hasTransportationDirtyMessageTarget) {
      controller.transportationDirtyMessageTarget.classList.toggle(
        "hidden",
        locked,
      )
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
      controller.transportationExpertSettingsTarget.classList.toggle(
        "hidden",
        !isExpertMode,
      )
    }

    // Save the expert mode setting
    this.settings.transportationExpertMode = isExpertMode
    SettingsManager.updateSetting("transportationExpertMode", isExpertMode)
  }

  /**
   * Update the display value for a transportation threshold slider (real-time feedback)
   */
  updateTransportationThresholdDisplay(event) {
    const input = event.target
    const name = input.name
    const value = parseFloat(input.value)
    const controller = this.controller
    const isMetric = this.getDistanceUnit() === "km"

    // Map input names to value target names and units
    const displayMap = {
      // Basic speed thresholds
      walkingMaxSpeed: {
        target: "walkingMaxSpeedValue",
        unit: isMetric ? "km/h" : "mph",
      },
      cyclingMaxSpeed: {
        target: "cyclingMaxSpeedValue",
        unit: isMetric ? "km/h" : "mph",
      },
      drivingMaxSpeed: {
        target: "drivingMaxSpeedValue",
        unit: isMetric ? "km/h" : "mph",
      },
      flyingMinSpeed: {
        target: "flyingMinSpeedValue",
        unit: isMetric ? "km/h" : "mph",
      },
      // Expert speed thresholds
      stationaryMaxSpeed: {
        target: "stationaryMaxSpeedValue",
        unit: isMetric ? "km/h" : "mph",
      },
      trainMinSpeed: {
        target: "trainMinSpeedValue",
        unit: isMetric ? "km/h" : "mph",
      },
      // Acceleration thresholds
      runningVsCyclingAccel: {
        target: "runningVsCyclingAccelValue",
        unit: "m/s²",
      },
      cyclingVsDrivingAccel: {
        target: "cyclingVsDrivingAccelValue",
        unit: "m/s²",
      },
      // Time thresholds
      minSegmentDuration: { target: "minSegmentDurationValue", unit: "sec" },
      timeGapThreshold: { target: "timeGapThresholdValue", unit: "sec" },
      // Distance threshold
      minFlightDistanceKm: {
        target: "minFlightDistanceValue",
        unit: isMetric ? "km" : "mi",
      },
    }

    const mapping = displayMap[name]
    if (!mapping) return

    const targetName = mapping.target
    const hasTarget = `has${targetName.charAt(0).toUpperCase()}${targetName.slice(1)}Target`

    if (controller[hasTarget]) {
      controller[`${targetName}Target`].textContent = `${value} ${mapping.unit}`
    }
  }

  // ===== Unit Conversion Helpers =====

  /**
   * Get user's preferred distance unit
   * @returns {string} 'km' or 'mi'
   */
  getDistanceUnit() {
    // Try to get from settings, default to 'km'
    return this.settings?.distanceUnit || "km"
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
    return Math.round((value / 0.621371) * 10) / 10 // mph to km/h
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
    return Math.round((value / 0.621371) * 10) / 10 // mi to km
  }

  /**
   * Update map style from settings
   */
  async updateMapStyle(event) {
    const styleName = event.target.value
    SettingsManager.updateSetting("mapStyle", styleName)

    const style = await getMapStyle(styleName)

    // Clear layer references
    this.layerManager.clearLayerReferences()

    this.map.setStyle(style)

    // Reload layers after style change
    this.map.once("style.load", () => {
      this.controller.loadMapData()
    })
  }

  /**
   * Reset settings to defaults
   */
  resetSettings() {
    if (confirm("Reset all settings to defaults? This will reload the page.")) {
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
    await SettingsManager.updateSetting("globeProjection", enabled)

    Toast.info("Globe view will be applied after page reload")

    // Prompt user to reload
    if (
      confirm("Globe view requires a page reload to take effect. Reload now?")
    ) {
      window.location.reload()
    }
  }

  /**
   * Update route opacity in real-time
   */
  updateRouteOpacity(event) {
    const opacity = parseInt(event.target.value, 10) / 100

    const routesLayer = this.layerManager.getLayer("routes")
    if (routesLayer && this.map.getLayer("routes")) {
      this.map.setPaintProperty("routes", "line-opacity", opacity)
    }

    SettingsManager.updateSetting("routeOpacity", opacity)
  }

  /**
   * Update advanced settings from form submission
   */
  async updateAdvancedSettings(event) {
    event.preventDefault()

    const formData = new FormData(event.target)
    const isMetric = this.getDistanceUnit() === "km"

    const settings = {
      routeOpacity: parseFloat(formData.get("routeOpacity")) / 100,
      fogOfWarRadius: parseInt(formData.get("fogOfWarRadius"), 10),
      fogOfWarThreshold: parseInt(formData.get("fogOfWarThreshold"), 10),
      metersBetweenRoutes: parseInt(formData.get("metersBetweenRoutes"), 10),
      minutesBetweenRoutes: parseInt(formData.get("minutesBetweenRoutes"), 10),
      pointsRenderingMode: formData.get("pointsRenderingMode"),
      speedColoredRoutes: formData.get("speedColoredRoutes") === "on",
    }

    // Collect transportation thresholds if present (convert from display units to metric)
    const basicThresholdFields = [
      "walkingMaxSpeed",
      "cyclingMaxSpeed",
      "drivingMaxSpeed",
      "flyingMinSpeed",
    ]
    const transportationThresholds = {}
    let hasTransportationThresholds = false

    basicThresholdFields.forEach((field) => {
      const value = formData.get(field)
      if (value !== null && value !== "") {
        transportationThresholds[field] = this.toMetricSpeed(
          parseFloat(value),
          isMetric,
        )
        hasTransportationThresholds = true
      }
    })

    if (hasTransportationThresholds) {
      settings.transportationThresholds = transportationThresholds
    }

    // Collect expert thresholds if expert mode is on
    const expertModeValue = formData.get("transportationExpertMode")
    if (expertModeValue === "on") {
      settings.transportationExpertMode = true

      const expertThresholds = {}
      let hasExpertThresholds = false

      // Speed thresholds
      const expertSpeedFields = ["stationaryMaxSpeed", "trainMinSpeed"]
      expertSpeedFields.forEach((field) => {
        const value = formData.get(field)
        if (value !== null && value !== "") {
          expertThresholds[field] = this.toMetricSpeed(
            parseFloat(value),
            isMetric,
          )
          hasExpertThresholds = true
        }
      })

      // Acceleration thresholds (no conversion)
      const accelFields = ["runningVsCyclingAccel", "cyclingVsDrivingAccel"]
      accelFields.forEach((field) => {
        const value = formData.get(field)
        if (value !== null && value !== "") {
          expertThresholds[field] = parseFloat(value)
          hasExpertThresholds = true
        }
      })

      // Time thresholds (no conversion)
      const timeFields = ["minSegmentDuration", "timeGapThreshold"]
      timeFields.forEach((field) => {
        const value = formData.get(field)
        if (value !== null && value !== "") {
          expertThresholds[field] = parseInt(value, 10)
          hasExpertThresholds = true
        }
      })

      // Distance threshold
      const minFlightDistance = formData.get("minFlightDistanceKm")
      if (minFlightDistance !== null && minFlightDistance !== "") {
        expertThresholds.minFlightDistanceKm = this.toMetricDistance(
          parseFloat(minFlightDistance),
          isMetric,
        )
        hasExpertThresholds = true
      }

      if (hasExpertThresholds) {
        settings.transportationExpertThresholds = expertThresholds
      }
    }

    // Update controller settings and dataLoader BEFORE applying,
    // so that loadMapData() sees the new values
    this.controller.settings = { ...this.controller.settings, ...settings }
    this.settings = this.controller.settings
    if (this.controller.dataLoader) {
      this.controller.dataLoader.updateSettings(this.controller.settings)
    }

    // Apply settings to current map (may trigger loadMapData)
    await this.applySettingsToMap(settings)

    // Save to backend
    for (const [key, value] of Object.entries(settings)) {
      await SettingsManager.updateSetting(key, value)
    }

    Toast.success("Settings updated successfully")
  }

  /**
   * Apply settings to map without reload
   */
  async applySettingsToMap(settings) {
    // Update route opacity
    if (settings.routeOpacity !== undefined) {
      const routesLayer = this.layerManager.getLayer("routes")
      if (routesLayer && this.map.getLayer("routes")) {
        this.map.setPaintProperty(
          "routes",
          "line-opacity",
          settings.routeOpacity,
        )
      }
    }

    // Update fog of war settings
    if (
      settings.fogOfWarRadius !== undefined ||
      settings.fogOfWarThreshold !== undefined
    ) {
      const fogLayer = this.layerManager.getLayer("fog")
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
    if (
      settings.pointsRenderingMode ||
      settings.speedColoredRoutes !== undefined
    ) {
      Toast.info("Reloading map data with new settings...")
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
