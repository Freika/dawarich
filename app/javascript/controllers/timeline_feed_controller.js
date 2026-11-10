import { Controller } from "@hotwired/stimulus"
import { monthPreview } from "./timeline_feed/month_preview"
import { openEntry } from "./timeline_feed/open_entry"
import { visitFilters } from "./timeline_feed/visit_filters"
import { visitSelection } from "./timeline_feed/visit_selection"

/**
 * Timeline Feed Controller (Unified Timeline)
 *
 * Coordinates the Timeline tab's calendar, visit list, and filters, and
 * dispatches events the MapLibre layer listens for.
 *
 * See docs/specs for contract details — event names and DOM attributes must match
 * what the views (Task 5), CSS (Task 6), and MapLibre layer/manager (Task 8) emit/expect.
 */
export default class TimelineFeedController extends Controller {
  static targets = [
    "visitListFrame",
    "scopeBadge",
    "searchInput",
    "emptyFiltered",
    "rowCheck",
    "selectionBar",
    "selectionForm",
    "selectionCount",
    "mergeButton",
    "deleteForm",
    "deleteButton",
  ]

  connect() {
    this.selectedDate = null
    this.selectedVisitId = null
    this.selectionMode = false
    this.selectedVisitIds = new Set()
    this.activeDayElement = null
    // When the visit list turbo-frame finishes loading, apply any pending
    // `visit_id=` URL-param selection (hydration is async because the frame
    // lazy-loads per-day data).
    this.pendingVisitId = null

    this.pendingTrackId = null
    this.pendingTrackTime = null

    // Browsers (Firefox especially) restore the search field's value on a
    // full page reload via the form-autocomplete cache, even with
    // autocomplete="off". Clear it explicitly so the rendered visit list
    // matches the URL state on a fresh load. Skip when an active query is
    // surfaced via URL (none today, but keeps this safe for future params).
    if (this.hasSearchInputTarget) this.searchInputTarget.value = ""

    this.boundKeyHandler = this.handleKey.bind(this)
    document.addEventListener("keydown", this.boundKeyHandler)

    // Clicking a visit pin on the map dispatches `timeline:open-visit`
    // (see event_handlers.js#handleVisitClick). Jump to the day and queue
    // the visit for halo selection.
    this.boundOpenVisit = this.handleOpenVisit.bind(this)
    document.addEventListener("timeline:open-visit", this.boundOpenVisit)

    // Clicking a track line on the map dispatches `timeline:open-track`
    // (see event_handlers.js#handleTrackClick). Jump to the day and expand
    // the matching journey entry inline.
    this.boundOpenTrack = this.handleOpenTrack.bind(this)
    document.addEventListener("timeline:open-track", this.boundOpenTrack)

    this.boundDateNavigated = (event) => {
      if (event.detail?.date) return
      this.selectedDate = null
      for (const el of this.element.querySelectorAll(".cal-cell--selected")) {
        el.classList.remove("cal-cell--selected")
      }
    }
    document.addEventListener(
      "timeline-feed:date-navigated",
      this.boundDateNavigated,
    )

    if (this.hasVisitListFrameTarget) {
      this.boundFrameLoad = this.handleVisitFrameLoad.bind(this)
      this.visitListFrameTarget.addEventListener(
        "turbo:frame-load",
        this.boundFrameLoad,
      )
    }

    // The calendar is rendered into a lazy turbo-frame, so the cell for the
    // URL-driven selected day doesn't exist when hydrateFromUrl() first runs.
    // Re-apply the highlight once the calendar frame finishes loading.
    this.boundCalendarLoad = (e) => {
      if (e.target?.id !== "timeline-calendar-frame") return
      if (!this.selectedDate) return
      const cell = this.element.querySelector(
        `[data-day="${this.selectedDate}"]`,
      )
      if (cell) cell.classList.add("cal-cell--selected")
    }
    document.addEventListener("turbo:frame-load", this.boundCalendarLoad)

    // Re-apply filter + search visibility after any turbo_stream update
    // (e.g., VisitsController#update replaces the row with fresh state, and
    // without this the newly-rendered row wouldn't honor the active filters).
    // Also fire `visit:updated` whenever a visit row is replaced or removed
    // or the day frame is replaced — VisitsController emits these streams on
    // edit / destroy / bulk actions, and the map's visits layer needs to
    // refetch so its dots reflect the new state.
    this.boundStreamRender = (event) => {
      const target = event?.detail?.newStream?.getAttribute?.("target") || ""
      const action = event?.detail?.newStream?.getAttribute?.("action") || ""
      const visitRowReplaced =
        (action === "replace" || action === "remove") &&
        target.startsWith("visit_entry_")
      const dayFrameUpdated =
        action === "update" && target === "timeline-feed-frame"

      requestAnimationFrame(() => {
        this.applyVisibility()
        if (visitRowReplaced || dayFrameUpdated) {
          document.dispatchEvent(new CustomEvent("visit:updated"))
        }
      })
    }
    document.addEventListener(
      "turbo:before-stream-render",
      this.boundStreamRender,
    )

    // URL params may drive initial day/status/place selection
    this.hydrateFromUrl()
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundKeyHandler)
    document.removeEventListener("timeline:open-visit", this.boundOpenVisit)
    document.removeEventListener("timeline:open-track", this.boundOpenTrack)
    document.removeEventListener(
      "timeline-feed:date-navigated",
      this.boundDateNavigated,
    )
    if (this.boundCalendarLoad) {
      document.removeEventListener("turbo:frame-load", this.boundCalendarLoad)
    }
    if (this.boundStreamRender) {
      document.removeEventListener(
        "turbo:before-stream-render",
        this.boundStreamRender,
      )
    }
    if (this.hasVisitListFrameTarget && this.boundFrameLoad) {
      this.visitListFrameTarget.removeEventListener(
        "turbo:frame-load",
        this.boundFrameLoad,
      )
    }
  }

  selectDay(event) {
    const cell = event.currentTarget
    const date = cell.dataset.day
    if (!date || cell.disabled) return
    this.navigateToDay(date)
  }

  navigateToDay(date, { fitBounds = true } = {}) {
    if (fitBounds) this.keepCameraOnDate = null
    // Fully SPA — no Turbo.visit. The map instance stays alive, layers
    // refetch in place, URL updates via pushState, panel state is preserved.
    // Three things happen in order:
    //   1. Panel UI (calendar selection + visit list frame src + scope badge)
    //   2. URL + top-of-page date form so browser state is consistent
    //   3. `timeline-feed:date-navigated` event — the maplibre controller
    //      refetches all enabled layers for the new range and fits bounds.
    this.applySelectedDayUI(date)

    const startAtLocal = `${date}T00:00:00`
    const endAtLocal = `${date}T23:59:59`

    this.alignRangeInputsToDay(date)

    const params = new URLSearchParams(window.location.search)
    params.set("start_at", startAtLocal)
    params.set("end_at", endAtLocal)
    params.set("panel", "timeline")
    params.set("date", date)
    window.history.pushState({}, "", `/map/v2?${params.toString()}`)

    document.dispatchEvent(
      new CustomEvent("timeline-feed:date-navigated", {
        detail: { date, startAt: startAtLocal, endAt: endAtLocal, fitBounds },
      }),
    )
  }

  // Pure UI update used by both navigateToDay (before Turbo.visit) and
  // selectDayByDate (after hydration on fresh page load).
  applySelectedDayUI(date) {
    this.selectedDate = date

    for (const el of this.element.querySelectorAll(".cal-cell--selected")) {
      el.classList.remove("cal-cell--selected")
    }
    const cell = this.element.querySelector(`[data-day="${date}"]`)
    if (cell) {
      cell.classList.add("cal-cell--selected")
    }

    // If the date is outside the calendar's currently-rendered month, fetch
    // the matching month so the cell becomes visible. `boundCalendarLoad`
    // re-applies `.cal-cell--selected` once the new cells are in the DOM.
    const calendarFrame = document.getElementById("timeline-calendar-frame")
    if (calendarFrame && !cell) {
      const month = date.slice(0, 7)
      const newSrc = `/map/timeline_feeds/calendar?month=${encodeURIComponent(month)}`
      if (calendarFrame.getAttribute("src") !== newSrc) {
        calendarFrame.setAttribute("src", newSrc)
      }
    }

    if (this.hasVisitListFrameTarget) {
      const start = `${date}T00:00:00`
      const end = `${date}T23:59:59`
      const newSrc = `/map/timeline_feeds?start_at=${encodeURIComponent(
        start,
      )}&end_at=${encodeURIComponent(end)}`
      // Force-fetch even when the URL appears identical (cache-control or
      // an in-flight request can otherwise leave the frame showing stale
      // entries when the user nudges day-by-day with the arrow keys).
      const frame = this.visitListFrameTarget
      if (frame.getAttribute("src") === newSrc) {
        frame.reload?.()
      } else {
        frame.setAttribute("src", newSrc)
      }
    }

    if (this.hasScopeBadgeTarget) {
      const d = new Date(`${date}T00:00:00`)
      this.scopeBadgeTarget.textContent = d.toLocaleDateString(undefined, {
        weekday: "short",
        month: "short",
        day: "numeric",
      })
    }
  }

  // Pure UI update — no navigation. Called on connect() when URL params
  // already reflect the date (hydrating after a Turbo page load) and from the
  // `timeline:open-visit` event path.
  selectDayByDate(date, alignInputs = true) {
    this.keepCameraOnDate = null
    if (this.selectionMode) this.exitSelection()
    this.applySelectedDayUI(date)
    if (alignInputs) this.alignRangeInputsToDay(date)

    // Tell the map — bounds are not known yet (visit list frame is async).
    // The map's visits_manager can re-center when it receives data, or listen
    // for additional events from the turbo-frame-rendered content.
    document.dispatchEvent(
      new CustomEvent("timeline-feed:day-selected", {
        detail: { date },
      }),
    )
  }

  // Collapse the top date-range form inputs to a single day. Navigation and
  // visit-pin selection do this so the form and panel stay in sync; URL
  // hydration passes alignInputs=false so the server-rendered inputs keep the
  // range's time component.
  alignRangeInputsToDay(date) {
    const startInput = document.querySelector('input[name="start_at"]')
    const endInput = document.querySelector('input[name="end_at"]')
    if (startInput) startInput.value = `${date}T00:00`
    if (endInput) endInput.value = `${date}T23:59`
  }

  // ---------- Visit selection ----------
  selectVisit(event) {
    if (this.selectionMode) {
      event.preventDefault()
      event.stopPropagation()
      const row = event.currentTarget
      const id = row.dataset.visitId
      if (!id) return
      this.toggleVisitId(id)
      return
    }

    // Don't trigger when activating a nested control: submit button, form
    // field, or anything inside the inline visit editor.
    if (
      event.target.closest("button[type='submit']") ||
      event.target.closest("input") ||
      event.target.closest("form")
    ) {
      return
    }

    // Space on a keyboard-focusable row would scroll the page — prevent that.
    if (event.key === " " || event.code === "Space") event.preventDefault?.()

    const row = event.currentTarget
    const visitId = Number.parseInt(row.dataset.visitId, 10)
    const lat = Number.parseFloat(row.dataset.visitLat)
    const lng = Number.parseFloat(row.dataset.visitLng)
    if (!Number.isFinite(visitId)) return

    this.selectedVisitId = visitId
    for (const el of this.element.querySelectorAll(".visit-row--selected")) {
      el.classList.remove("visit-row--selected")
    }
    row.classList.add("visit-row--selected")

    document.dispatchEvent(
      new CustomEvent("timeline-feed:visit-selected", {
        detail: {
          visitId,
          lat: Number.isFinite(lat) ? lat : null,
          lng: Number.isFinite(lng) ? lng : null,
        },
      }),
    )
  }

  // Low-confidence rows are display-gated by CSS via a day-level class so
  // the search/filter `hidden` mechanics stay untouched.
  toggleLowConfidence(event) {
    const button = event.currentTarget
    const day = button.closest(".timeline-day")
    if (!day) return
    const open = day.classList.toggle("timeline-day--show-lowconf")
    button.setAttribute("aria-expanded", String(open))
    this.applyVisibility()
  }

  // ---------- Journey entries (track segments between visits) ----------
  toggleTrackInfo(event) {
    const target = event.currentTarget
    const frameId = target.dataset.frameId
    const trackId = target.dataset.trackId
    const frame = document.getElementById(frameId)
    if (!frame) return

    const chevron = target.querySelector(".track-info-chevron")
    const isHidden = frame.classList.contains("hidden")

    if (isHidden) {
      frame.classList.remove("hidden")
      if (!frame.getAttribute("src")) {
        frame.src = `/map/timeline_feeds/${trackId}/track_info`
      }
      if (chevron) chevron.style.transform = "rotate(180deg)"

      const connector = target.closest(
        '.timeline-entry[data-entry-type="journey"]',
      )
      if (connector) {
        const { startedAt, endedAt } = connector.dataset
        document.dispatchEvent(
          new CustomEvent("timeline-feed:entry-click", {
            detail: { trackId, startedAt, endedAt },
          }),
        )
      }
    } else {
      frame.classList.add("hidden")
      if (chevron) chevron.style.transform = ""
      document.dispatchEvent(new CustomEvent("timeline-feed:entry-deselect"))
    }
  }

  entryHover(event) {
    const el = event.currentTarget
    const { entryType, startedAt, endedAt, trackId, visitId } = el.dataset
    if (!startedAt || !endedAt) return
    document.dispatchEvent(
      new CustomEvent("timeline-feed:entry-hover", {
        detail: { entryType, startedAt, endedAt, trackId, visitId },
      }),
    )
  }

  entryUnhover() {
    document.dispatchEvent(new CustomEvent("timeline-feed:entry-unhover"))
  }

  navigateDay(event) {
    const direction = event.currentTarget.dataset.direction
    const current = this.selectedDate || this.renderedDay()
    if (!current) return
    // Work in UTC throughout to avoid local-timezone drift. `new Date("YYYY-MM-DDT00:00:00")`
    // is parsed as local, then toISOString() converts to UTC — which can shift
    // the date by ±1 in non-UTC timezones. Using Date.UTC + setUTCDate is stable.
    const [y, m, day] = current.split("-").map(Number)
    const d = new Date(Date.UTC(y, m - 1, day))
    const delta = direction === "prev" ? -1 : direction === "next" ? 1 : 0
    d.setUTCDate(d.getUTCDate() + delta)
    const newDate = d.toISOString().slice(0, 10)
    this.navigateToDay(newDate)
  }

  renderedDay() {
    return (
      document.querySelector('input[name="end_at"]')?.value.slice(0, 10) || null
    )
  }

  // ---------- Keyboard ----------
  handleKey(e) {
    if (e.target.matches?.("input, textarea, select")) return
    if (e.target.isContentEditable) return
    if (e.target.closest?.(".maplibregl-canvas-container")) return
    if (e.altKey || e.metaKey || e.ctrlKey || e.shiftKey) return
    if (
      document.querySelector(
        ".modal.modal-open, dialog[open], #video-studio:not(.hidden), #poster-studio:not(.hidden)",
      )
    )
      return
    if (!this.element.closest(".map-control-panel.open .tab-content.active"))
      return

    if (e.key === "ArrowLeft") {
      this.navigateInDirection("prev")
    } else if (e.key === "ArrowRight") {
      this.navigateInDirection("next")
    }
  }

  navigateInDirection(direction) {
    const fakeEvent = { currentTarget: { dataset: { direction } } }
    this.navigateDay(fakeEvent)
  }
}

Object.assign(
  TimelineFeedController.prototype,
  visitFilters,
  visitSelection,
  openEntry,
  monthPreview,
)
