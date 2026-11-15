import { translate } from "i18n"
import { Toast } from "maps_maplibre/components/toast"
import { isGatedPlan } from "maps_maplibre/utils/layer_gate"
import { SettingsManager } from "maps_maplibre/utils/settings_manager"
import { MapStyleSettings } from "./map_style_settings"
import { syncSettingsForm } from "./settings_form_sync"

/**
 * Handles all settings-related operations for Maps V2
 * Including toggles, advanced settings, and UI synchronization
 */
export class SettingsController {
  constructor(controller) {
    this.controller = controller
    this.settings = controller.settings
    this.style = new MapStyleSettings(controller, this)
  }

  /** Kept here for callers outside the map, e.g. the theme editor. */
  applyMapStyle(styleName) {
    return this.style.applyMapStyle(styleName)
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
    if (!SettingsManager.loaded) {
      Toast.error(translate("settings.load_failed"))
    }

    // Update dataLoader with new settings
    if (this.controller.dataLoader) {
      this.controller.dataLoader.updateSettings(this.settings)
    }

    return this.settings
  }

  /**
   * Sync UI controls with loaded settings
   */
  /** Seed every settings form control from the loaded settings. */
  syncToggleStates() {
    syncSettingsForm(this)
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
   * Restore the map appearance to the server defaults, then reload
   */
  async resetSettings() {
    if (!confirm(translate("settings.confirm_reset"))) return

    this.cancelLayerColorSaves()
    if (await SettingsManager.resetToDefaults()) {
      window.location.reload()
    } else {
      Toast.error(translate("settings.reset_failed"))
    }
  }

  togglePointsEditing(event) {
    const enabled = event.target.checked

    this.layerManager.getLayer("map-editor")?.setEditable(enabled)

    SettingsManager.updateSetting("pointDraggingEnabled", enabled)
  }

  syncPointsEditAvailability() {
    const controller = this.controller
    if (!controller.hasPointsEditToggleTarget) return

    const input = controller.pointsEditToggleTarget
    const gated = isGatedPlan(controller.userPlanValue)

    input.disabled = gated
    input.checked =
      SettingsManager.getSetting("pointDraggingEnabled") === true && !gated

    // A hover tooltip cannot explain a disabled control to touch or keyboard,
    // so the reason also renders as a line under the row.
    if (controller.hasPointsEditUnavailableNoteTarget) {
      const note = controller.pointsEditUnavailableNoteTarget
      note.textContent = ""
      note.classList.add("hidden")
    }

    const label = input.closest("label")
    if (!label) return
    label.classList.toggle("opacity-40", gated)
    label.style.cursor = gated ? "not-allowed" : ""
  }

  /** Track color applies immediately; saving is debounced while dragging. */
  updateTrackColor(event) {
    const color = event.target.value
    this.applyTrackColor(color)
    this.syncLayerColorLabel("trackColor", color)
    this.scheduleLayerColorSave("trackColor", color)
  }

  async resetLayerColors() {
    this.cancelLayerColorSaves()

    const settings = await SettingsManager.resetToDefaults(["track_color"])
    if (!settings) {
      Toast.error(translate("settings.reset_failed"))
      return
    }
    this.settings.trackColor = settings.trackColor
    this.syncTrackColorPicker(settings.trackColor)
    this.applyTrackColor(settings.trackColor)
  }

  syncTrackColorPicker(color) {
    const input = this.controller.element.querySelector(
      'input[name="trackColor"]',
    )
    if (input && color) input.value = color
    this.syncLayerColorLabel("trackColor", color)
  }

  applyTrackColor(color) {
    this.layerManager.getLayer("tracks-mvt")?.setColors({ trackColor: color })
  }

  toggleSpeedColoredRoutes(event) {
    SettingsManager.updateSetting("speedColoredRoutes", event.target.checked)
    this.applySpeedColoring()
  }

  updateSpeedColorScale(event) {
    SettingsManager.updateSetting("speedColorScale", event.detail.colorStops)
    this.applySpeedColoring()
  }

  applySpeedColoring() {
    this.layerManager.getLayer("tracks-mvt")?.setSpeedColoring({
      enabled: SettingsManager.getSetting("speedColoredRoutes") === true,
      scale: SettingsManager.getSetting("speedColorScale"),
    })
    this.layerManager.getLayer("map-editor")?.reapplyTileFilters()
  }

  syncLayerColorLabel(key, color) {
    const label = this.controller.element.querySelector(
      `[data-layer-color-value="${key}"]`,
    )
    if (label && color) label.textContent = color.toUpperCase()
  }

  // A pending save landing after a reset would restore the old colour.
  cancelLayerColorSaves() {
    Object.values(this.layerColorTimers || {}).forEach(clearTimeout)
    this.layerColorTimers = {}
  }

  scheduleLayerColorSave(key, color) {
    this.layerColorTimers = this.layerColorTimers || {}
    clearTimeout(this.layerColorTimers[key])
    this.layerColorTimers[key] = setTimeout(() => {
      SettingsManager.updateSetting(key, color)
    }, 150)
  }

  updateDistanceUnit(event) {
    const unit = event.target.value
    this.settings.distance_unit = unit
    this.controller.rangeStatistics?.setUnit(unit)
    SettingsManager.updateSetting("distance_unit", unit)
  }
}
