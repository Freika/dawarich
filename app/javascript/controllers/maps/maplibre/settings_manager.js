import { translate } from "i18n"
import { Toast } from "maps_maplibre/components/toast"
import { UpgradeBanner } from "maps_maplibre/components/upgrade_banner"
import {
  classifyBasemapUrl,
  styleDocumentFailed,
} from "maps_maplibre/utils/basemap_url"
import { isGatedPlan } from "maps_maplibre/utils/layer_gate"
import {
  bulkPointsRequired,
  LAYER_COLOR_DEFAULTS,
  SettingsManager,
  tiledPointsActive,
} from "maps_maplibre/utils/settings_manager"
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
      pointsEditToggle: "pointDraggingEnabled",
      pointsTiledToggle: "pointsTiledRendering",
      routesToggle: "routesVisible",
      heatmapToggle: "heatmapEnabled",
      hexagonsToggle: "hexagonsEnabled",
      visitsToggle: "visitsEnabled",
      photosToggle: "photosEnabled",
      areasToggle: "areasEnabled",
      placesToggle: "placesEnabled",
      fogToggle: "fogEnabled",
      scratchToggle: "scratchEnabled",
      familyToggle: "familyEnabled",
      speedColoredToggle: "speedColoredRoutes",
      tracksToggle: "tracksEnabled",
      flightsToggle: "flightsEnabled",
      anomaliesToggle: "anomaliesEnabled",
    }

    // Gated layer toggles that Lite users cannot persist
    const gatedToggles = new Set([
      "heatmapToggle",
      "hexagonsToggle",
      "fogToggle",
      "scratchToggle",
      "pointsEditToggle",
    ])

    Object.entries(toggleMap).forEach(([targetName, settingKey]) => {
      const target = `${targetName}Target`
      const hasTarget = `has${targetName.charAt(0).toUpperCase()}${targetName.slice(1)}Target`
      if (controller[hasTarget]) {
        // Force gated layers off for Lite users on page load
        if (
          gatedToggles.has(targetName) &&
          isGatedPlan(controller.userPlanValue)
        ) {
          controller[target].checked = false
        } else {
          controller[target].checked = this.settings[settingKey]
        }
      }
    })

    this.syncPointsEditAvailability()
    this.syncRouteSplittingAvailability()
    this.syncTiledRenderingNote()

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

    // Sync layer color pickers
    Object.entries(LAYER_COLOR_DEFAULTS).forEach(([key, fallback]) => {
      const color = this.settings[key] || fallback
      const input = controller.element.querySelector(`input[name="${key}"]`)
      if (input) input.value = color
      this.syncLayerColorLabel(key, color)
    })

    // Sync distance unit radio
    const distanceUnitInput = controller.element.querySelector(
      `input[name="distanceUnit"][value="${this.getDistanceUnit()}"]`,
    )
    if (distanceUnitInput) distanceUnitInput.checked = true

    // Sync vector tiles URL input
    const tilesUrlInput = controller.element.querySelector(
      'input[name="vectorTilesUrl"]',
    )
    if (tilesUrlInput) tilesUrlInput.value = this.settings.vectorTilesUrl || ""

    const tilesFallbackInput = controller.element.querySelector(
      'input[name="tilesFallback"]',
    )
    if (tilesFallbackInput) {
      tilesFallbackInput.checked = this.settings.tilesFallback === true
    }
    this.syncTilesFallbackAvailability()

    // Sync map style dropdown. Setting .value doesn't fire "change", so
    // notify the map-theme-editor controller separately — it shows/hides
    // the custom color block based on the synced style.
    const mapStyleSelect = controller.element.querySelector(
      'select[name="mapStyle"]',
    )
    if (mapStyleSelect) {
      mapStyleSelect.value = this.settings.mapStyle || "light"
      this.syncStyleDependentToggles(this.settings.mapStyle || "light")
      document.dispatchEvent(
        new CustomEvent("map-style:synced", {
          detail: { style: this.settings.mapStyle || "light" },
        }),
      )
    }

    // Sync globe projection toggle (force off for Lite users)
    if (controller.hasGlobeToggleTarget) {
      controller.globeToggleTarget.checked = isGatedPlan(
        controller.userPlanValue,
      )
        ? false
        : this.settings.globeProjection || false
    }

    // Sync fog of war mode radio
    const fogModeInput = controller.element.querySelector(
      `input[name="fogOfWarMode"][value="${this.settings.fogOfWarMode || "points"}"]`,
    )
    if (fogModeInput) {
      fogModeInput.checked = true
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

    // Sync city statistics settings
    const minMinutesInput = controller.element.querySelector(
      'input[name="minMinutesSpentInCity"]',
    )
    if (minMinutesInput) {
      minMinutesInput.value = this.settings.minMinutesSpentInCity || 60
      if (controller.hasMinMinutesInCityValueTarget) {
        controller.minMinutesInCityValueTarget.textContent = `${minMinutesInput.value} min`
      }
    }

    const maxGapInput = controller.element.querySelector(
      'input[name="maxGapMinutesInCity"]',
    )
    if (maxGapInput) {
      maxGapInput.value = this.settings.maxGapMinutesInCity || 120
      if (controller.hasMaxGapMinutesValueTarget) {
        controller.maxGapMinutesValueTarget.textContent = `${maxGapInput.value} min`
      }
    }

    // Sync GPS noise filtering settings
    const gpsFilteringToggle = controller.element.querySelector(
      'input[name="gpsFilteringEnabled"]',
    )
    if (gpsFilteringToggle) {
      gpsFilteringToggle.checked = this.settings.gpsFilteringEnabled !== false
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

    // All form inputs are seeded now — let the dirty tracker snapshot them
    document.dispatchEvent(new CustomEvent("map-settings:synced"))
  }

  /**
   * Sync transportation mode settings with loaded values
   */
  async syncTransportationSettings() {
    const controller = this.controller

    // Sync enabled transportation modes allowlist
    if (controller.hasEnabledModeCheckboxTarget) {
      const enabled = this.settings.enabledTransportationModes
      if (Array.isArray(enabled)) {
        const enabledSet = new Set(enabled.map(String))
        controller.enabledModeCheckboxTargets.forEach((checkbox) => {
          checkbox.checked = enabledSet.has(checkbox.value)
        })
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
    document.dispatchEvent(
      new CustomEvent("map-settings:saved", {
        detail: { scope: "transportation" },
      }),
    )
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
        controller.transportationDirtyMessageTarget.textContent = translate(
          "settings.unsaved_transportation_changes",
        )
        controller.transportationDirtyMessageTarget.classList.add(
          "text-warning",
        )
        controller.transportationDirtyMessageTarget.classList.remove(
          "text-base-content/60",
        )
      } else {
        controller.transportationDirtyMessageTarget.textContent = translate(
          "settings.make_changes_to_apply",
        )
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
    // Show confirmation dialog
    const confirmed = confirm(
      translate("settings.confirm_transportation_recalculation"),
    )

    if (!confirmed) return

    await this.saveEnabledTransportationModes()
  }

  /**
   * Save the enabled transportation modes allowlist to backend.
   * (Threshold settings are gone — detection tunes itself.)
   */
  async saveEnabledTransportationModes() {
    const controller = this.controller

    if (!controller.hasEnabledModeCheckboxTarget) return

    const enabledTransportationModes = controller.enabledModeCheckboxTargets
      .filter((checkbox) => checkbox.checked)
      .map((checkbox) => checkbox.value)

    this.settings.enabledTransportationModes = enabledTransportationModes

    const result = await SettingsManager.updateSetting(
      "enabledTransportationModes",
      enabledTransportationModes,
    )

    // Check result and update UI
    if (result && result.status === "locked") {
      Toast.error(
        translate(
          "messages.cannot_update_recalculation_is_already_in_progress",
        ),
      )
      // Immediately lock the UI
      this.setTransportationSettingsLocked(true)
      // Also start polling for status updates
      this.startRecalculationPolling()
      return
    }

    if (result?.recalculation_triggered) {
      Toast.info(translate("settings.transportation_recalculation_started"))
      this.resetTransportationDirtyState()
      // Immediately lock the UI since recalculation started
      this.setTransportationSettingsLocked(true)
      // Start polling for status updates
      this.startRecalculationPolling()
    } else {
      Toast.success(translate("messages.transportation_settings_saved"))
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
        text.textContent = translate(
          "settings.transportation_recalculation_progress",
          {
            processed: processedFormatted,
            total: totalFormatted,
            progress,
          },
        )

        container.appendChild(spinner)
        container.appendChild(text)
        alertEl.appendChild(container)
        alertEl.classList.remove("hidden", "alert-success", "alert-error")
        alertEl.classList.add("alert-warning")
      } else if (isCompleted) {
        const text = document.createElement("span")
        text.textContent = translate(
          "settings.transportation_recalculation_completed",
        )

        alertEl.appendChild(text)
        alertEl.classList.remove("hidden", "alert-warning", "alert-error")
        alertEl.classList.add("alert-success")
        // Auto-hide after 5 seconds
        setTimeout(() => alertEl.classList.add("hidden"), 5000)
        // Reset dirty state so apply button shows correct message
        this.resetTransportationDirtyState()
      } else if (isFailed) {
        const text = document.createElement("span")
        text.textContent = translate(
          "settings.transportation_recalculation_failed",
          {
            error: status.error_message || translate("common.unknown_error"),
          },
        )

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

    // Lock the enabled-mode checkboxes
    if (controller.hasEnabledModeCheckboxTarget) {
      controller.enabledModeCheckboxTargets.forEach((checkbox) => {
        checkbox.disabled = locked
        checkbox.classList.toggle("opacity-50", locked)
        checkbox.classList.toggle("cursor-not-allowed", locked)
      })
    }

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
   * Get user's preferred distance unit
   * @returns {string} 'km' or 'mi'
   */
  getDistanceUnit() {
    // Try to get from settings, default to 'km'
    return this.settings?.distance_unit || "km"
  }

  /**
   * Update map style from settings
   */
  async updateMapStyle(event) {
    const styleName = event.target.value
    SettingsManager.updateSetting("mapStyle", styleName)
    await this.applyMapStyle(styleName)
  }

  /**
   * Apply a style to the live map and reload app layers on top.
   * Also called by the map-theme-editor controller to re-apply the
   * custom theme after a preset or token change.
   */
  async applyMapStyle(styleName) {
    this.syncStyleDependentToggles(styleName)
    const style = await getMapStyle(styleName, {
      ...this.mapStyleOptions(),
      vectorTilesUrl: SettingsManager.getSetting("vectorTilesUrl"),
    })

    // Clear layer references
    this.layerManager.clearLayerReferences()

    if (typeof style === "string") {
      this.applyUserStyleUrl(style, styleName)
      return
    }

    this.swapStyle(style)
  }

  // MapLibre only fires style.load when it builds a Style from scratch. Its
  // default path diffs the new document into the live style and stays silent,
  // which would leave the app layers stripped and never re-added, so the
  // rebuild has to be forced.
  swapStyle(style) {
    this.map.once("style.load", () => this.restoreStyleLayers())
    this.map.setStyle(style, { diff: false })
  }

  mapStyleOptions() {
    return {
      hiddenTileCategories:
        SettingsManager.getSetting("hiddenTileCategories") || [],
      disabledPoiGroups: SettingsManager.getSetting("disabledPoiGroups") || [],
      customTheme: SettingsManager.getSetting("customTheme"),
      tilesFallback: SettingsManager.getSetting("tilesFallback") === true,
    }
  }

  // Reload layers after a style change. setStyle replaces the whole style
  // document — including the projection — so globe mode must be restored
  // or every style/theme change silently drops back to mercator.
  restoreStyleLayers() {
    this.restoreGlobeProjection()
    this.controller.loadMapData()
  }

  applyUserStyleUrl(styleUrl, styleName) {
    let settled = false

    const onLoad = () => {
      if (settled) return
      settled = true
      this.map.off("error", onError)
      this.restoreStyleLayers()
    }

    // MapLibre reports every failed request through `error`, tiles included.
    // Only a failure of the style document may discard the user's basemap —
    // one unreachable tile from an otherwise valid style must not.
    const onError = async (event) => {
      if (settled || !styleDocumentFailed(event, styleUrl)) return
      settled = true
      this.map.off("style.load", onLoad)
      this.map.off("error", onError)
      Toast.error(translate("settings.custom_style_load_failed"))
      const fallback = await getMapStyle(styleName, this.mapStyleOptions())
      this.swapStyle(fallback)
    }

    this.map.once("style.load", onLoad)
    this.map.on("error", onError)
    this.map.setStyle(styleUrl, { diff: false })
  }

  restoreGlobeProjection() {
    const globe = this.settings.globeProjection
    if (globe !== true && globe !== "true") return

    this.map.setProjection({ type: "globe" })
    this.map.setSky({
      "atmosphere-blend": [
        "interpolate",
        ["linear"],
        ["zoom"],
        0,
        1,
        5,
        1,
        7,
        0,
      ],
    })
  }

  /**
   * Reset settings to defaults
   */
  resetSettings() {
    if (confirm(translate("settings.confirm_reset"))) {
      SettingsManager.resetToDefaults()
      window.location.reload()
    }
  }

  /**
   * Toggle globe projection
   * Requires page reload to apply since projection is set at map initialization
   */
  async toggleGlobe(event) {
    const toggle = event.target
    const enabled = toggle.checked

    if (enabled && isGatedPlan(this.controller.userPlanValue)) {
      // Globe can't do a timed preview (requires reload), so just show upgrade prompt
      toggle.checked = false
      UpgradeBanner.show({
        message: translate("messages.globe_view_is_a_pro_feature"),
        upgradeUrl: this.controller.upgradeUrlValue,
        utmContent: "globe_view",
      })
      return
    }

    await SettingsManager.updateSetting("globeProjection", enabled)

    Toast.info(
      translate("messages.globe_view_will_be_applied_after_page_reload"),
    )

    // Prompt user to reload
    if (confirm(translate("settings.confirm_globe_reload"))) {
      window.location.reload()
    }
  }

  /**
   * Update route opacity in real-time
   */
  async updateFogMode(event) {
    const mode = event.target.value

    const fogLayer = this.layerManager.getLayer("fog")
    if (fogLayer) {
      fogLayer.setMode(mode)
    }

    await SettingsManager.updateSetting("fogOfWarMode", mode)
    await this.controller.routesManager?.reapplyPointsRenderer()
  }

  togglePointsEditing(event) {
    const enabled = event.target.checked

    this.layerManager.getLayer("points")?.setEditMode(enabled)

    SettingsManager.updateSetting("pointDraggingEnabled", enabled)
  }

  // Dim Edit points while tiled rendering is on. The saved preference survives.
  // Tiles are pointless while another layer already needs the whole point set
  syncTiledRenderingNote() {
    const controller = this.controller
    if (!controller.hasPointsTiledInactiveNoteTarget) return

    const settings = SettingsManager.getSettings()
    const note = controller.pointsTiledInactiveNoteTarget
    const inactive =
      settings.pointsTiledRendering === true && bulkPointsRequired(settings)

    note.classList.toggle("hidden", !inactive)
    if (!inactive) return

    // Routes and fog ride tile sources now — Scratch map is the only layer
    // left that needs the whole point set.
    const blockers = [
      settings.scratchEnabled &&
        translate("map.tiled_rendering.blockers.scratch"),
    ].filter(Boolean)

    note.textContent = translate("map.tiled_rendering.inactive_note", {
      layers: blockers.join(", "),
      count: blockers.length,
    })
  }

  syncPointsEditAvailability() {
    const controller = this.controller
    if (!controller.hasPointsEditToggleTarget) return

    const input = controller.pointsEditToggleTarget
    const tiled = tiledPointsActive(SettingsManager.getSettings())

    // Keep the checkbox in step with the layer's real edit mode.
    input.disabled = tiled
    input.checked =
      !tiled &&
      SettingsManager.getSetting("pointDraggingEnabled") === true &&
      !isGatedPlan(controller.userPlanValue)

    // A hover tooltip cannot explain a disabled control to touch or keyboard,
    // so the reason also renders as a line under the row.
    if (controller.hasPointsEditUnavailableNoteTarget) {
      const note = controller.pointsEditUnavailableNoteTarget
      note.textContent = tiled
        ? translate("map.tiled_rendering.editing_unavailable")
        : ""
      note.classList.toggle("hidden", !tiled)
    }

    const label = input.closest("label")
    if (!label) return
    label.classList.toggle("opacity-40", tiled)
    label.style.cursor = tiled ? "not-allowed" : ""
  }

  // The route-splitting sliders shape the polylines the CLASSIC path builds
  // from raw points; under tiled mode backend track boundaries replace client
  // splitting entirely, so the inputs dim rather than silently no-op.
  syncRouteSplittingAvailability() {
    const controller = this.controller
    const tiled = tiledPointsActive(SettingsManager.getSettings())

    for (const name of ["metersBetweenRoutes", "minutesBetweenRoutes"]) {
      const input = controller.element.querySelector(`input[name="${name}"]`)
      if (!input) continue
      input.disabled = tiled
      const section = input.closest(".form-control")
      if (section) {
        section.classList.toggle("opacity-40", tiled)
        section.style.cursor = tiled ? "not-allowed" : ""
      }
    }

    if (controller.hasRouteSplittingUnavailableNoteTarget) {
      const note = controller.routeSplittingUnavailableNoteTarget
      note.textContent = tiled
        ? translate("map.tiled_rendering.splitting_unavailable")
        : ""
      note.classList.toggle("hidden", !tiled)
    }
  }

  updateRouteOpacity(event) {
    const opacity = parseInt(event.target.value, 10) / 100

    const routesLayer = this.layerManager.getLayer("routes")
    if (routesLayer && this.map.getLayer("routes")) {
      this.map.setPaintProperty("routes", "line-opacity", opacity)
    }

    // Under tiled mode the slider drives the track-tile line instead of
    // silently no-oping against the unpopulated classic layer.
    this.layerManager.getLayer("tracks-mvt")?.setRouteOpacity(opacity)

    SettingsManager.updateSetting("routeOpacity", opacity)
  }

  /**
   * Layer colors (routes / tracks): paint applies immediately, the save
   * is debounced because color inputs fire rapidly while dragging.
   */
  updateRouteColor(event) {
    const color = event.target.value
    this.applyRouteColor(color)
    this.syncLayerColorLabel("routeColor", color)
    this.scheduleLayerColorSave("routeColor", color)
  }

  updateTrackColor(event) {
    const color = event.target.value
    this.applyTrackColor(color)
    this.syncLayerColorLabel("trackColor", color)
    this.scheduleLayerColorSave("trackColor", color)
  }

  resetLayerColors() {
    Object.values(this.layerColorTimers || {}).forEach(clearTimeout)
    this.layerColorTimers = {}

    Object.entries(LAYER_COLOR_DEFAULTS).forEach(([key, color]) => {
      const input = this.controller.element.querySelector(
        `input[name="${key}"]`,
      )
      if (input) input.value = color
      this.syncLayerColorLabel(key, color)
    })
    SettingsManager.updateSettings(LAYER_COLOR_DEFAULTS)
    this.applyRouteColor(LAYER_COLOR_DEFAULTS.routeColor)
    this.applyTrackColor(LAYER_COLOR_DEFAULTS.trackColor)
  }

  applyRouteColor(color) {
    if (this.map.getLayer("routes")) {
      this.map.setPaintProperty("routes", "line-color", [
        "case",
        ["has", "color"],
        ["get", "color"],
        color,
      ])
    }
    if (this.map.getLayer("routes-base")) {
      this.map.setPaintProperty("routes-base", "line-color", color)
    }
    this.layerManager.getLayer("tracks-mvt")?.setColors({ routeColor: color })
  }

  applyTrackColor(color) {
    if (this.map.getLayer("tracks")) {
      this.map.setPaintProperty("tracks", "line-color", color)
    }
    this.layerManager.getLayer("tracks-mvt")?.setColors({ trackColor: color })
  }

  syncLayerColorLabel(key, color) {
    const label = this.controller.element.querySelector(
      `[data-layer-color-value="${key}"]`,
    )
    if (label) label.textContent = color.toUpperCase()
  }

  scheduleLayerColorSave(key, color) {
    this.layerColorTimers = this.layerColorTimers || {}
    clearTimeout(this.layerColorTimers[key])
    this.layerColorTimers[key] = setTimeout(() => {
      SettingsManager.updateSetting(key, color)
    }, 150)
  }

  /**
   * Base map tile categories / POI groups (moved from /settings/maps).
   * Unchecked toggles form the hidden/disabled lists; the style is
   * rebuilt live so changes are visible immediately.
   */
  async toggleTileCategory() {
    const hidden = this.uncheckedValues("data-tile-category")
    await SettingsManager.updateSetting("hiddenTileCategories", hidden)
    this.applyMapStyle(SettingsManager.getSetting("mapStyle"))
  }

  async togglePoiGroup() {
    const disabled = this.uncheckedValues("data-poi-group")
    await SettingsManager.updateSetting("disabledPoiGroups", disabled)
    this.applyMapStyle(SettingsManager.getSetting("mapStyle"))
  }

  uncheckedValues(attribute) {
    return Array.from(
      this.controller.element.querySelectorAll(`input[${attribute}]`),
    )
      .filter((input) => !input.checked)
      .map((input) => input.getAttribute(attribute))
  }

  /**
   * The Custom style draws no labels or POIs, so their toggles are
   * disabled while it's active, with a tooltip explaining why. A raster or
   * foreign-style basemap carries no Protomaps layers at all, so there every
   * toggle goes dead, not just the unsupported ones — except under a raster
   * basemap with the fallback on, where the default vector stack is composed
   * underneath and the toggles still control what shows through the gaps.
   */
  syncStyleDependentToggles(styleName) {
    const basemap = classifyBasemapUrl(
      SettingsManager.getSetting("vectorTilesUrl"),
    )
    const fallback = SettingsManager.getSetting("tilesFallback") === true
    const foreignBasemap =
      (basemap === "raster" && !fallback) || basemap === "style"
    const custom = styleName === "custom"
    const inputs = this.controller.element.querySelectorAll(
      "input[data-tile-category], input[data-poi-group]",
    )
    inputs.forEach((input) => {
      const unavailable =
        foreignBasemap || (custom && input.dataset.customSupported !== "true")
      input.disabled = unavailable

      const label = input.closest("label")
      if (!label) return
      label.classList.toggle("opacity-40", unavailable)
      label.classList.toggle("tooltip", unavailable)
      label.style.cursor = unavailable ? "not-allowed" : ""
      if (unavailable) {
        label.dataset.tip = foreignBasemap
          ? translate("settings.layer_unavailable_foreign_basemap")
          : translate("settings.layer_unavailable_custom_style")
      } else {
        delete label.dataset.tip
      }
    })
  }

  updateDistanceUnit(event) {
    const unit = event.target.value
    this.settings.distance_unit = unit
    SettingsManager.updateSetting("distance_unit", unit)
  }

  updateVectorTilesUrl(event) {
    const raw = event.target.value.trim()

    if (!SettingsManager.validVectorTilesUrl(raw)) {
      Toast.error(translate("settings.invalid_tile_url"))
      return
    }

    SettingsManager.updateSetting("vectorTilesUrl", raw || null)
    this.syncTilesFallbackAvailability()
    this.applyMapStyle(SettingsManager.getSetting("mapStyle"))
  }

  async updateTilesFallback(event) {
    await SettingsManager.updateSetting("tilesFallback", event.target.checked)
    this.applyMapStyle(SettingsManager.getSetting("mapStyle"))
  }

  /**
   * The fallback only means something for XYZ tile URLs. A style document
   * replaces the whole style, leaving nothing to draw the default basemap
   * under, and with no custom URL there is nothing to fall back from.
   */
  syncTilesFallbackAvailability() {
    const input = this.controller.element.querySelector(
      'input[name="tilesFallback"]',
    )
    if (!input) return

    const basemap = classifyBasemapUrl(
      SettingsManager.getSetting("vectorTilesUrl"),
    )
    const unavailable = basemap !== "raster" && basemap !== "vector"
    input.disabled = unavailable

    const label = input.closest("label")
    if (!label) return
    label.classList.toggle("opacity-40", unavailable)
    label.classList.toggle("tooltip", unavailable)
    if (unavailable) {
      label.dataset.tip = translate("settings.tiles_fallback_unavailable")
    } else {
      delete label.dataset.tip
    }
  }

  /**
   * Update advanced settings from form submission
   */
  async updateAdvancedSettings(event) {
    event.preventDefault()

    const formData = new FormData(event.target)

    const settings = {
      routeOpacity: parseFloat(formData.get("routeOpacity")) / 100,
      fogOfWarRadius: parseInt(formData.get("fogOfWarRadius"), 10),
      fogOfWarThreshold: parseInt(formData.get("fogOfWarThreshold"), 10),
      metersBetweenRoutes: parseInt(formData.get("metersBetweenRoutes"), 10),
      minutesBetweenRoutes: parseInt(formData.get("minutesBetweenRoutes"), 10),
      pointsRenderingMode: formData.get("pointsRenderingMode"),
      speedColoredRoutes: formData.get("speedColoredRoutes") === "on",
      minMinutesSpentInCity: parseInt(
        formData.get("minMinutesSpentInCity"),
        10,
      ),
      maxGapMinutesInCity: parseInt(formData.get("maxGapMinutesInCity"), 10),
      gpsFilteringEnabled: formData.get("gpsFilteringEnabled") === "on",
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

    document.dispatchEvent(
      new CustomEvent("map-settings:saved", { detail: { scope: "form" } }),
    )

    Toast.success(translate("messages.settings_updated_successfully"))
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
      Toast.info(translate("messages.reloading_map_data_with_new_settings"))
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

  updateMinMinutesInCityDisplay(event) {
    if (this.controller.hasMinMinutesInCityValueTarget) {
      this.controller.minMinutesInCityValueTarget.textContent = `${event.target.value} min`
    }
  }

  updateMaxGapMinutesDisplay(event) {
    if (this.controller.hasMaxGapMinutesValueTarget) {
      this.controller.maxGapMinutesValueTarget.textContent = `${event.target.value} min`
    }
  }

  async reapplyAnomalyFilter() {
    if (!window.confirm(translate("settings.confirm_reapply_anomaly_filter"))) {
      return
    }

    const apiKey = this.controller.apiKeyValue
    if (!apiKey) {
      Toast.error(
        translate("messages.api_key_not_available_please_reload_the_page"),
      )
      return
    }

    try {
      const response = await fetch("/api/v1/points/reapply_anomaly_filter", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${apiKey}`,
          "Content-Type": "application/json",
        },
      })

      if (!response.ok) {
        throw new Error(`Request failed: ${response.status}`)
      }

      Toast.success(translate("settings.re_evaluation_queued"))
    } catch (error) {
      console.error("[Settings] reapplyAnomalyFilter failed:", error)
      Toast.error(
        translate("messages.could_not_queue_re_evaluation_please_try_again"),
      )
    }
  }

  async recalculateUserData() {
    if (!window.confirm(translate("settings.confirm_recalculate_user_data"))) {
      return
    }

    const apiKey = this.controller.apiKeyValue
    if (!apiKey) {
      Toast.error(
        translate("messages.api_key_not_available_please_reload_the_page"),
      )
      return
    }

    try {
      const response = await fetch("/api/v1/recalculations", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${apiKey}`,
          "Content-Type": "application/json",
        },
      })

      if (!response.ok) {
        throw new Error(`Request failed: ${response.status}`)
      }

      Toast.success(translate("settings.recalculation_queued"))
    } catch (error) {
      console.error("[Settings] recalculateUserData failed:", error)
      Toast.error(
        translate("messages.could_not_queue_recalculation_please_try_again"),
      )
    }
  }
}
