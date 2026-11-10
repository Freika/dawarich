import { translate } from "i18n"
import {
  defaultSettings,
  normalizeSettings,
  rangeRestorePlan,
  readProvenance,
} from "video_studio/studio_state"

/**
 * Video studio settings: theme, colours, mode, format and saved-settings restore.
 * Mixed into the controller; `this` is the controller.
 */
export const settingsPanel = {
  selectTheme(event) {
    this.settings.theme = event.currentTarget.dataset.themeKey
    this.settingsChanged()
  },

  resetTrackColor() {
    this.settings.track_color = defaultSettings().track_color
    this.settingsChanged()
  },

  resetFogColor() {
    this.settings.fog_color = defaultSettings().fog_color
    this.settingsChanged()
  },

  selectVisualizationMode(event) {
    this.settings.visualization_mode =
      event.currentTarget.dataset.visualizationMode
    this.settingsChanged()
  },

  selectFormat(event) {
    this.settings.format = event.currentTarget.dataset.format
    this.settingsChanged()
  },

  updateSetting(event) {
    const { setting } = event.currentTarget.dataset
    const input = event.currentTarget
    const value =
      input.type === "checkbox"
        ? input.checked
        : input.type === "range" || input.type === "number"
          ? Number(input.value)
          : input.value

    this.settings[setting] = value
    this.settingsChanged()
  },

  // Re-seeds the studio from an expired video's stored recipe (option C: the
  // row outlives the blob, so the settings are enough to make it again).
  async restoreSettings(event) {
    if (this.rendering || this.rangeLoading) return
    const operation = this.startOperation()
    let raw = null
    try {
      raw = JSON.parse(event.currentTarget.dataset.settings)
      this.settings = normalizeSettings(raw)
    } catch {
      this.settings = defaultSettings()
    }
    this.syncControls()
    const restored = await this.restoreRange(readProvenance(raw), operation)
    if (!restored || !this.operationIsCurrent(operation)) return
    await this.settingsChanged(operation)
    if (!this.operationIsCurrent(operation)) return
    this.syncDateTimeControls()
  },

  // Styling alone is not the recipe: a video made from a different date range
  // has to bring that range back, or "re-render" quietly rebuilds whatever the
  // page is showing now under the old video's looks.
  async restoreRange(provenance, operation = this.startOperation()) {
    const plan = rangeRestorePlan(
      provenance,
      this.provider.dateRange(),
      this.provider,
    )
    if (plan.action === "none") return true

    const warn = () => {
      this.statusTarget.textContent = translate("video.range_mismatch", {
        range: plan.range,
      })
    }
    if (plan.action === "warn") {
      warn()
      return true
    }

    this.clearResult()
    this.style = null
    this.setRangeBusy(true)
    this.statusTarget.textContent = translate("video.restoring_range")
    try {
      await this.provider.applyDates(plan.start_at, plan.end_at)
      if (!this.operationIsCurrent(operation)) return false
      await this.reloadTrack(operation)
      if (!this.operationIsCurrent(operation)) return false
      this.statusTarget.textContent = ""
      return true
    } catch {
      // A reload that never lands leaves the old track in place, which is the
      // route the user did not ask for — say so rather than render it.
      if (this.operationIsCurrent(operation)) warn()
      return false
    } finally {
      if (this.operationIsCurrent(operation)) this.setRangeBusy(false)
    }
  },
}
