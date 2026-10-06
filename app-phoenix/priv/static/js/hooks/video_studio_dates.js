import { translate } from "i18n"
import Flash from "controllers/flash_controller"
import {
  formatDateTimeRange,
  selectableDateTimeRange,
  toLocalDateTimeInput,
} from "video_studio/date_range"
import { loadTrack } from "video_studio/load_track"
import { toVideoPoints } from "video_studio/points"
import { buildRouteClock } from "video_studio/route_clock"
import { buildRouteTimeline } from "video_studio/route_timeline"
import {
  defaultSettings,
  normalizeSettings,
  rangeRestorePlan,
  readProvenance,
} from "video_studio/studio_state"
import { computeTrackStats } from "video_studio/video_stats"

export const dates = {
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
      if (this.operationIsCurrent(operation)) warn()
      return false
    } finally {
      if (this.operationIsCurrent(operation)) this.setRangeBusy(false)
    }
  },
  syncDateTimeControls() {
    const editable = Boolean(this.provider?.supportsDateNavigation)
    if (this.hasRangeControlsTarget) {
      this.rangeControlsTarget.classList.toggle("hidden", !editable)
    }
    if (this.hasRangeDisplayTarget) {
      this.rangeDisplayTarget.classList.toggle("hidden", editable)
    }
    if (!editable || !this.hasDateStartTarget || !this.hasDateEndTarget) return

    const { startAt, endAt } = this.provider.dateRange()
    const timeZone = this.provider.timeZone?.()
    this.dateStartTarget.value = toLocalDateTimeInput(startAt, timeZone)
    this.dateEndTarget.value = toLocalDateTimeInput(endAt, timeZone)
  },
  async applyDateTimeRange() {
    if (
      !this.provider?.supportsDateNavigation ||
      this.rendering ||
      this.rangeLoading
    )
      return
    const range = selectableDateTimeRange(
      this.dateStartTarget.value,
      this.dateEndTarget.value,
      this.provider.timeZone?.(),
    )
    if (!range) {
      this.dateEndTarget.setCustomValidity(
        translate("datetime.start_before_end"),
      )
      this.dateEndTarget.reportValidity()
      return
    }

    this.dateEndTarget.setCustomValidity("")
    const currentRangeLabel = this.hasRangeLabelTarget
      ? this.rangeLabelTarget.textContent
      : this.dateRangeLabel()
    const nameWasAuto = this.nameInputTarget.value === currentRangeLabel
    const operation = this.startOperation()
    this.clearResult()
    this.style = null
    this.setRangeBusy(true)
    this.statusTarget.textContent = translate("poster.loading_tracks")
    try {
      await this.provider.applyDates(range.start, range.end)
      if (!this.operationIsCurrent(operation)) return
      await this.reloadTrack(operation)
      if (!this.operationIsCurrent(operation)) return
      this.syncDateTimeControls()
      if (nameWasAuto) this.nameInputTarget.value = this.dateRangeLabel()
      await this.refreshStyle(operation)
      if (!this.operationIsCurrent(operation)) return
      this.renderStats()
    } catch (error) {
      if (this.operationIsCurrent(operation)) {
        Flash.show(
          "error",
          translate("video.open_failed", { error: error.message }),
        )
      }
    } finally {
      if (this.operationIsCurrent(operation)) {
        this.statusTarget.textContent = ""
        this.setRangeBusy(false)
      }
    }
  },
  setRangeBusy(value) {
    this.rangeLoading = value
    if (this.hasLoadButtonTarget) this.loadButtonTarget.disabled = value
    if (this.hasLoadSpinnerTarget) {
      this.loadSpinnerTarget.classList.toggle("hidden", !value)
    }
    if (this.hasDateStartTarget) this.dateStartTarget.disabled = value
    if (this.hasDateEndTarget) this.dateEndTarget.disabled = value
    if (this.hasSwitchButtonTarget) this.switchButtonTarget.disabled = value
    if (value && this.hasSaveButtonTarget) this.saveButtonTarget.disabled = true
    this.syncRenderAvailability()
  },
  async reloadTrack(operation = null) {
    const { trackGeojson, points } = await loadTrack(this.provider)
    if (operation !== null && !this.operationIsCurrent(operation)) return
    this.trackGeojson = trackGeojson
    this.points = toVideoPoints(points)
    this.stats = computeTrackStats(this.points)
    this.clock = buildRouteClock(this.points)
    this.timeline = buildRouteTimeline(this.trackGeojson, { smooth: true })
    if (this.hasRangeLabelTarget) {
      this.rangeLabelTarget.textContent = this.dateRangeLabel()
    }
  },
  dateRangeLabel() {
    const { startAt, endAt } = this.provider.dateRange()
    return formatDateTimeRange(
      startAt,
      endAt,
      document.documentElement.lang || undefined,
      this.provider.timeZone?.(),
    )
  },
}
