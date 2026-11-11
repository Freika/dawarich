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
  static targets = ["start", "end", "mobileLabel", "dayLink"]

  static values = {
    locale: String,
    timezone: String,
    dateFormat: String,
    monthNames: Array,
    abbrMonthNames: Array,
  }

  connect() {
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
    this.updateShareLink()

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

  // The Share button (in the map's button cluster) offers the period on
  // screen, not the one the page was loaded with.
  updateShareLink() {
    const link = globalThis.document?.querySelector?.(
      '[data-testid="timeline-share-button"]',
    )
    if (!link) return
    const url = new URL(link.href, window.location.href)
    url.searchParams.set("start_date", this.startTarget.value.slice(0, 10))
    url.searchParams.set("end_date", this.endTarget.value.slice(0, 10))
    link.href = url.toString()
  }

  updateDayLinks(startAt, endAt) {
    for (const link of this.dayLinkTargets) {
      const shift = (value) => {
        const local = rangeInputValue(value, this.timezoneValue)
        const seconds = isWallClockValue(value)
          ? value.slice(16, 19) || ":00"
          : `:${String(new Date(value).getUTCSeconds()).padStart(2, "0")}`
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
}
