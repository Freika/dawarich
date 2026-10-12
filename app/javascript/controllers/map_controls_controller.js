import { Controller } from "@hotwired/stimulus"
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
  static targets = ["panel", "toggleIcon", "start", "end", "mobileLabel"]

  static values = {
    locale: String,
    timezone: String,
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

    const wallClock = isWallClockValue(startAt)
    const start = new Date(
      wallClock ? `${startAt.slice(0, 10)}T12:00:00Z` : startAt,
    )
    if (this.hasMobileLabelTarget && !Number.isNaN(start.valueOf())) {
      this.mobileLabelTarget.textContent = new Intl.DateTimeFormat(
        this.localeValue || undefined,
        {
          year: "numeric",
          month: "long",
          day: "numeric",
          timeZone: wallClock ? "UTC" : this.timezoneValue,
        },
      ).format(start)
    }
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
