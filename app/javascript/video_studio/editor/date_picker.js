import Flash from "controllers/flash_controller"
import { translate } from "i18n"
import {
  selectableDateTimeRange,
  toLocalDateTimeInput,
} from "video_studio/date_range"

/**
 * Video studio date range inputs and applying the chosen range.
 * Mixed into VideoStudioController; `this` is the VideoStudioController.
 */
export const datePicker = {
  // Date changes stay inside the open studio. Map-backed providers update the
  // main map in place; trip-backed providers keep their fixed range display.
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
    // The provider mutates its range before a failed map reload rejects. The
    // visible range label only changes after a successful track reload, so it
    // remains the reliable reference for whether this name is automatic.
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
}
