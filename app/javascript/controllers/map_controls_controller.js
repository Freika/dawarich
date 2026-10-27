import { Controller } from "@hotwired/stimulus"
import { formatDate } from "i18n"
import { toLocalDateTimeInput } from "video_studio/date_range"

function rangeInputValue(value, timeZone) {
  // Timeline day navigation deliberately sends wall-clock values without an
  // offset. Keep those exact fields; only convert absolute timestamps emitted
  // by Studio or received from the server into the user's timezone.
  if (isWallClockValue(value)) {
    return value.slice(0, 16)
  }
  return toLocalDateTimeInput(value, timeZone)
}

function isWallClockValue(value) {
  return /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2})?$/.test(value)
}

export default class extends Controller {
  static targets = [
    "panel",
    "toggleIcon",
    "start",
    "end",
    "mobileLabel",
    "dayLink",
  ]

  static values = {
    locale: String,
    timezone: String,
    dateFormat: String,
    monthNames: Array,
    abbrMonthNames: Array,
  }

  connect() {
    // Restore panel state from sessionStorage on page load
    const panelState = sessionStorage.getItem("mapControlsPanelState")
    if (panelState === "visible") {
      this.showPanel()
    }

    this.boundDateNavigated = this.dateNavigated.bind(this)
    document.addEventListener(
      "timeline-feed:date-navigated",
      this.boundDateNavigated,
    )
  }

  disconnect() {
    document.removeEventListener(
      "timeline-feed:date-navigated",
      this.boundDateNavigated,
    )
  }

  dateNavigated(event) {
    const { startAt, endAt } = event.detail || {}
    if (!startAt || !endAt) return

    this.startTarget.value = rangeInputValue(startAt, this.timezoneValue)
    this.endTarget.value = rangeInputValue(endAt, this.timezoneValue)

    this.updateDayLinks(startAt, endAt)

    const wallClock = isWallClockValue(startAt)
    const start = new Date(
      wallClock ? `${startAt.slice(0, 10)}T12:00:00Z` : startAt,
    )
    if (this.hasMobileLabelTarget && !Number.isNaN(start.valueOf())) {
      this.mobileLabelTarget.textContent = formatDate(start, {
        locale: this.localeValue || undefined,
        month: "long",
        timeZone: wallClock ? "UTC" : this.timezoneValue,
      })
    }
  }

  updateDayLinks(startAt, endAt) {
    for (const link of this.dayLinkTargets) {
      const shift = (value) => {
        const local = rangeInputValue(value, this.timezoneValue)
        const seconds = isWallClockValue(value)
          ? value.slice(16, 19) || ":00"
          : ":00"
        const date = new Date(`${local}${seconds}Z`)
        date.setUTCDate(date.getUTCDate() + Number(link.dataset.dayOffset))
        return date.toISOString().slice(0, 19)
      }
      const start = shift(startAt)
      const url = new URL(link.href, window.location.href)
      const current = new URLSearchParams(window.location.search)
      for (const key of ["import_id", "panel"]) {
        if (current.has(key)) url.searchParams.set(key, current.get(key))
      }
      url.searchParams.delete("date")
      url.searchParams.set("start_at", start)
      url.searchParams.set("end_at", shift(endAt))
      link.href = url.toString()
      link.closest("[data-tip]").dataset.tip = this.humanDate(start)
    }
  }

  humanDate(value) {
    const date = new Date(`${value}Z`)
    const day = date.getUTCDate()
    const month = date.getUTCMonth() + 1
    const tokens = {
      "%Y": String(date.getUTCFullYear()),
      "%m": String(month).padStart(2, "0"),
      "%d": String(day).padStart(2, "0"),
      "%-d": String(day),
      "%e": String(day).padStart(2, " "),
      "%B": this.monthNamesValue[month],
      "%b": this.abbrMonthNamesValue[month],
    }
    return this.dateFormatValue.replace(
      /%(?:-d|[YmdBeb])/g,
      (token) => tokens[token],
    )
  }

  toggle() {
    const isHidden = this.panelTarget.classList.contains("hidden")

    if (isHidden) {
      this.showPanel()
      sessionStorage.setItem("mapControlsPanelState", "visible")
    } else {
      this.hidePanel()
      sessionStorage.setItem("mapControlsPanelState", "hidden")
    }
  }

  showPanel() {
    this.panelTarget.classList.remove("hidden")

    // Update icon to chevron-up
    const currentIcon = this.toggleIconTarget.querySelector("svg")
    currentIcon.classList.remove("lucide-chevron-down")
    currentIcon.classList.add("lucide-chevron-up")
    currentIcon.innerHTML = '<path d="m18 15-6-6-6 6"/>'
  }

  hidePanel() {
    this.panelTarget.classList.add("hidden")

    // Update icon to chevron-down
    const currentIcon = this.toggleIconTarget.querySelector("svg")
    currentIcon.classList.remove("lucide-chevron-up")
    currentIcon.classList.add("lucide-chevron-down")
    currentIcon.innerHTML = '<path d="m6 9 6 6 6-6"/>'
  }
}
