/**
 * A period of several days. The feed renders every day of the period as a
 * closed <details>. The open one is the selected day: the map dims the rest,
 * replay jumps to it. Nothing is refetched, the period stays loaded.
 * Mixed into TimelineFeedController; `this` is the TimelineFeedController.
 */
export const periodDays = {
  showRange() {
    const start = document.querySelector('input[name="start_at"]')?.value
    const end = document.querySelector('input[name="end_at"]')?.value
    if (!this.periodSpansDays() || !this.hasVisitListFrameTarget) return false

    this.selectedDate = null
    this.visitListFrameTarget.setAttribute(
      "src",
      `/map/timeline_feeds?start_at=${encodeURIComponent(start)}&end_at=${encodeURIComponent(end)}`,
    )
    return true
  },

  // Same rule as the server: a period is more than a day long.
  periodSpansDays() {
    const start = document.querySelector('input[name="start_at"]')?.value
    const end = document.querySelector('input[name="end_at"]')?.value
    // A whole day is 25 hours long when the clocks go back, and still one
    // day; a timed period that long has its ends on two dates.
    const hours = (new Date(end) - new Date(start)) / 3600000
    return hours > 25 || (hours > 24 && start.slice(0, 10) !== end.slice(0, 10))
  },

  // Enter in the search field looks through every note the user wrote, not
  // only the days on screen. An empty search brings the days back.
  searchNotes() {
    if (!this.hasVisitListFrameTarget) return
    const query = this.searchInputTarget.value.trim()
    if (!query) {
      if (!this.showRange()) this.applySelectedDayUI(this.renderedDay())
      return
    }
    this.visitListFrameTarget.setAttribute(
      "src",
      `/map/timeline_feeds?q=${encodeURIComponent(query)}`,
    )
  },

  // `date=` in the URL of a period selects that day, once per URL.
  applyUrlDay() {
    const search = window.location.search
    const date = new URLSearchParams(search).get("date")
    if (!date || this.appliedUrlDay === search || !this.rangeDay(date)) return
    this.appliedUrlDay = search
    this.selectInRange(date)
  },

  rangeDay(date) {
    if (!date || !this.hasVisitListFrameTarget) return null
    return this.visitListFrameTarget.querySelector(
      `details.timeline-day[data-day="${date}"]`,
    )
  },

  selectInRange(date, { keepCamera = false } = {}) {
    const day = this.rangeDay(date)
    if (!day) return false
    if (keepCamera) this.keepCameraOnDate = date
    day.open = true
    day.scrollIntoView({ behavior: "smooth", block: "nearest" })
    return true
  },

  showAllDays() {
    const open = this.rangeDay(this.selectedDate)
    if (open) open.open = false
  },

  // Fired by every day <details>. Opening one closes the previous one (shared
  // `name`), so read the result from the DOM instead of trusting event order.
  dayToggled() {
    const open = this.visitListFrameTarget.querySelector(
      "details.timeline-day[open]",
    )
    const day = open?.dataset.day || null
    if (day === this.selectedDate) return
    if (this.selectionMode) this.exitSelection()
    this.selectedDate = day
    this.syncAllDays()

    if (!day) {
      document.dispatchEvent(new CustomEvent("timeline-feed:day-collapsed"))
      return
    }
    let bounds = null
    if (this.keepCameraOnDate !== day) {
      try {
        bounds = JSON.parse(open.dataset.bounds || "null")
      } catch {
        // Malformed bounds JSON — select the day without moving the map
      }
    }
    this.keepCameraOnDate = null
    document.dispatchEvent(
      new CustomEvent("timeline-feed:day-expanded", {
        detail: { day, bounds },
      }),
    )
  },

  // After the frame (re)renders: keep the selected day open, or forget it
  // when the new content no longer has it.
  syncRange() {
    const selected = this.rangeDay(this.selectedDate)
    if (selected) {
      selected.open = true
    } else if (
      this.visitListFrameTarget.querySelector(".timeline-range-head")
    ) {
      this.selectedDate = null
    }
    this.applyUrlDay()
    this.syncAllDays()
  },

  // "All days" is there to leave the selected day.
  syncAllDays() {
    if (this.hasAllDaysButtonTarget) {
      this.allDaysButtonTarget.hidden = !this.rangeDay(this.selectedDate)
    }
  },

  // A period picked in the calendar, as wall-clock values. Like
  // navigateToDay, nothing reloads: the URL, the date fields and the map
  // follow. A whole single day goes the same way as any other day.
  navigateToPeriod(startAt, endAt) {
    const day = endAt.slice(0, 10)
    const wholeDay =
      startAt === `${day}T00:00:00` && endAt === `${day}T23:59:59`
    if (wholeDay) {
      this.navigateToDay(day)
      return
    }
    if (this.selectionMode) this.exitSelection()
    this.selectedDate = null

    const startInput = document.querySelector('input[name="start_at"]')
    const endInput = document.querySelector('input[name="end_at"]')
    if (startInput) startInput.value = startAt.slice(0, 16)
    if (endInput) endInput.value = endAt.slice(0, 16)

    const params = new URLSearchParams(window.location.search)
    params.set("start_at", startAt)
    params.set("end_at", endAt)
    params.delete("date")
    params.delete("month")
    window.history.pushState({}, "", `/map/v2?${params.toString()}`)

    // Part of one day still reads as that day.
    if (!this.showRange()) this.applySelectedDayUI(day)
    document.dispatchEvent(
      new CustomEvent("timeline-feed:date-navigated", {
        detail: { startAt, endAt, fitBounds: true },
      }),
    )
  },

  // A note row: mark it and let the map show where it was written.
  selectNote(event) {
    // The pencil opens the edit dialog; Turbo needs that click to bubble.
    if (event.target.closest?.("a")) return
    const row = event.currentTarget
    for (const el of this.element.querySelectorAll(".note-leg--selected")) {
      el.classList.remove("note-leg--selected")
    }
    row.classList.add("note-leg--selected")
    const lat = Number.parseFloat(row.dataset.noteLat)
    const lng = Number.parseFloat(row.dataset.noteLng)
    document.dispatchEvent(
      new CustomEvent("timeline-feed:note-selected", {
        detail: {
          id: Number(row.dataset.noteId),
          lat: Number.isFinite(lat) ? lat : null,
          lng: Number.isFinite(lng) ? lng : null,
        },
      }),
    )
  },
}
