import { translate } from "i18n"
import {
  calendarPresetRange,
  selectableDateTimeRange,
  toLocalDateTimeInput,
} from "video_studio/date_range"

/**
 * Poster date range inputs: seeding, presets and loading the chosen range.
 * Mixed into the controller; `this` is the controller.
 */
export const datePicker = {
  seedDateInputs() {
    if (!this.hasDateStartTarget || !this.hasDateEndTarget) return
    const { startAt, endAt } = this.provider.dateRange()
    if (!startAt) return
    this.dateStartTarget.value = toLocalDateTimeInput(
      startAt,
      this.provider.timeZone?.(),
    )
    this.dateEndTarget.value = toLocalDateTimeInput(
      endAt,
      this.provider.timeZone?.(),
    )
  },

  // SPA date change delegated to the provider — the studio never closes.
  async applyDates() {
    if (!this.provider?.supportsDateNavigation) return
    const start = this.dateStartTarget.value
    const end = this.dateEndTarget.value
    if (!start || !end) return
    const range = selectableDateTimeRange(
      start,
      end,
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

    const subtitleWasAuto =
      this.subtitleInputTarget.value === this.dateRangeLabel()
    this.setLoadBusy(true)
    this.setStatus(translate("poster.loading_tracks"))
    try {
      await this.provider.applyDates(range.start, range.end)
      await this.provider.ensureTrackLoaded()

      if (subtitleWasAuto)
        this.subtitleInputTarget.value = this.dateRangeLabel()
      this.previewMap?.setStyle(this.posterStyle())
      this.recenter()
      this.syncSaveAvailability()
    } finally {
      this.setLoadBusy(false)
      this.setStatus("")
    }
  },

  setLoadBusy(value) {
    this.rangeLoading = value
    if (this.hasLoadButtonTarget) {
      this.loadButtonTarget.disabled = value
      this.loadSpinnerTarget.classList.toggle("hidden", !value)
      this.loadLabelTarget.textContent = translate(
        value ? "poster.loading" : "poster.load",
      )
    }
    if (this.hasSwitchButtonTarget) this.switchButtonTarget.disabled = value
  },

  presetRange(event) {
    const range = calendarPresetRange(
      event.currentTarget.dataset.range,
      new Date(),
      this.provider.timeZone?.(),
    )
    if (!range) return
    this.dateStartTarget.value = range.start
    this.dateEndTarget.value = range.end
    this.applyDates()
  },
}
