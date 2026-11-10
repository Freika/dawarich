import { Controller } from "@hotwired/stimulus"
import { translate } from "i18n"

/**
 * Timeline Feed Controller (Unified Timeline)
 *
 * Coordinates the Timeline tab's calendar, visit list, and filters, and
 * dispatches events the MapLibre layer listens for.
 *
 * See docs/specs for contract details — event names and DOM attributes must match
 * what the views (Task 5), CSS (Task 6), and MapLibre layer/manager (Task 8) emit/expect.
 */
export default class extends Controller {
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
    "allDaysButton",
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
      if (!event.detail?.date) this.selectedDate = null
      this.syncAllDays()
    }
    // The period picker says what was picked; the period is ours.
    this.boundPickRange = (event) =>
      this.navigateToPeriod(event.detail.startAt, event.detail.endAt)
    document.addEventListener("period-picker:range", this.boundPickRange)
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

    // Replay moved into another day of the period: when a day is selected,
    // the selection follows it (the camera stays with the replay marker).
    this.boundReplayDay = (event) => {
      const day = event.detail?.day
      if (!this.rangeDay(this.selectedDate) || this.selectedDate === day) return
      this.selectInRange(day, { keepCamera: true })
    }
    document.addEventListener("replay:day-changed", this.boundReplayDay)

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
        if (dayFrameUpdated) this.syncRange()
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
    document.removeEventListener("replay:day-changed", this.boundReplayDay)
    document.removeEventListener("period-picker:range", this.boundPickRange)
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

  handleOpenVisit(event) {
    const { visitId, date } = event.detail || {}
    if (Number.isFinite(Number(visitId))) {
      this.pendingVisitId = Number(visitId)
    }
    if (date) this.selectDayByDate(date)
  }

  handleOpenTrack(event) {
    const { trackId, date, startAtMs, endAtMs } = event.detail || {}
    const tid = Number.parseInt(trackId, 10)

    if (Number.isFinite(tid)) {
      this.pendingTrackId = tid
    } else if (Number.isFinite(Number(startAtMs))) {
      // Route click: no track id, so focus the journey whose time range
      // overlaps the route's. Both are epoch ms, so the match is tz-safe.
      this.pendingTrackTime = {
        startAtMs: Number(startAtMs),
        endAtMs: Number.isFinite(Number(endAtMs))
          ? Number(endAtMs)
          : Number(startAtMs),
      }
    } else {
      return
    }

    // If the clicked track is on the already-selected day, the journey
    // entry is already rendered — expand it immediately. Otherwise navigate
    // to the day; the frame-load handler consumes the pending target once the
    // new day's entries render.
    if (date && this.selectInRange(date, { keepCamera: true })) {
      this._tryExpandPendingTrack()
      return
    }

    this.keepCameraOnDate = date || this.selectedDate
    if (date && date !== this.selectedDate) {
      this.navigateToDay(date, { fitBounds: false })
    } else {
      this._tryExpandPendingTrack()
    }
  }

  // ---------- URL hydration ----------
  hydrateFromUrl() {
    const params = new URLSearchParams(window.location.search)
    if (params.get("panel") !== "timeline") return

    // Status filter
    const status = params.get("status")
    if (status) {
      for (const cb of this.element.querySelectorAll(
        'input[type="checkbox"][data-status]',
      )) {
        cb.checked = cb.dataset.status === status
      }
      this.filterChanged()
    }

    // Date selection — "today" means the user's local today, not UTC today.
    // Using toISOString() would shift the date near midnight in non-UTC zones.
    // Fall back to the range's end date when there's no explicit `date=` param
    // (arriving via the top date-range form / Search / Last 7 days) so the
    // panel lands on the most recent day of the range instead of going blank —
    // keeping the range and the panel in sync (C1).
    // A period of several days opens as a whole; a `date=` beside it picks
    // the day to select once the period has rendered (see applyUrlDay).
    if (this.showRange()) return

    const date = params.get("date") || this.renderedDay()
    if (date) {
      const isoDate =
        date === "today" ? new Date().toLocaleDateString("en-CA") : date
      requestAnimationFrame(() => this.selectDayByDate(isoDate, false))
    }

    // Specific visit selection — deferred until the visit list frame loads
    // (see handleVisitFrameLoad). Supports deep links (`?visit_id=N`) and
    // same-page navigation dispatched via the `timeline:open-visit` event.
    const visitId = params.get("visit_id")
    if (visitId) {
      const parsedVisit = Number.parseInt(visitId, 10)
      if (Number.isFinite(parsedVisit)) this.pendingVisitId = parsedVisit
    }
  }

  handleVisitFrameLoad() {
    // Reapply the current filter + search state to newly-rendered rows so
    // user intent ("hide declined" / "search: café") persists across day switches.
    this.applyVisibility()

    // Extract the day's bounds from the rendered DOM and re-dispatch
    // day-selected with bounds so the map can fit to the visits.
    this.syncRange()

    // A period has no single day to fit the map to.
    const dayEl = this.visitListFrameTarget.querySelector(
      ".timeline-range-head",
    )
      ? null
      : this.visitListFrameTarget.querySelector(".timeline-day")
    const keepCamera =
      this.pendingTrackId ||
      this.pendingTrackTime ||
      this.keepCameraOnDate === this.selectedDate
    if (dayEl?.dataset?.bounds && !keepCamera) {
      try {
        const bounds = JSON.parse(dayEl.dataset.bounds)
        if (bounds && typeof bounds === "object") {
          document.dispatchEvent(
            new CustomEvent("timeline-feed:day-selected", {
              detail: { date: this.selectedDate, bounds },
            }),
          )
        }
      } catch {
        // Malformed bounds JSON — silently skip fit
      }
    }

    if (this.pendingTrackId || this.pendingTrackTime) {
      this._tryExpandPendingTrack()
    }

    this.selectPendingVisit()
  }

  selectPendingVisit() {
    if (!this.pendingVisitId) return
    const row = this.element.querySelector(
      `[data-visit-id="${this.pendingVisitId}"]`,
    )
    this.pendingVisitId = null
    if (!row) return
    // Synthesize a Stimulus-shaped event and run through the normal path so
    // visual selection + the `timeline-feed:visit-selected` dispatch are consistent.
    this.selectVisit({ currentTarget: row, target: row })
  }

  // ---------- A period of several days ----------
  // The feed renders every day of the period as a closed <details>. The open
  // one is the selected day: the map dims the rest, replay jumps to it, the
  // calendar marks it. Nothing is refetched, the period stays loaded.
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
  }

  // Same rule as the server: a period is more than a day long.
  periodSpansDays() {
    const start = document.querySelector('input[name="start_at"]')?.value
    const end = document.querySelector('input[name="end_at"]')?.value
    return new Date(end) - new Date(start) > 86400000
  }

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
  }

  // `date=` in the URL of a period selects that day, once per URL.
  applyUrlDay() {
    const search = window.location.search
    const date = new URLSearchParams(search).get("date")
    if (!date || this.appliedUrlDay === search || !this.rangeDay(date)) return
    this.appliedUrlDay = search
    this.selectInRange(date)
  }

  rangeDay(date) {
    if (!date || !this.hasVisitListFrameTarget) return null
    return this.visitListFrameTarget.querySelector(
      `details.timeline-day[data-day="${date}"]`,
    )
  }

  selectInRange(date, { keepCamera = false } = {}) {
    const day = this.rangeDay(date)
    if (!day) return false
    if (keepCamera) this.keepCameraOnDate = date
    day.open = true
    day.scrollIntoView({ behavior: "smooth", block: "nearest" })
    return true
  }

  showAllDays() {
    const open = this.rangeDay(this.selectedDate)
    if (open) open.open = false
  }

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
  }

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
  }

  // "All days" is there to leave the selected day.
  syncAllDays() {
    if (this.hasAllDaysButtonTarget) {
      this.allDaysButtonTarget.hidden = !this.rangeDay(this.selectedDate)
    }
  }

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
  }

  // Expands the journey entry for `this.pendingTrackId` if it's present in
  // the currently rendered day. Idempotent — re-clicking the same track
  // collapses via `toggleTrackInfo`, but programmatic expansion only opens
  // a closed entry, never collapses an open one.
  _tryExpandPendingTrack() {
    let toggle = null

    if (this.pendingTrackId) {
      const tid = this.pendingTrackId
      this.pendingTrackId = null
      toggle = this.element.querySelector(
        `.journey-leg[data-track-id="${tid}"]`,
      )
    } else if (this.pendingTrackTime) {
      const { startAtMs, endAtMs } = this.pendingTrackTime
      this.pendingTrackTime = null
      toggle = this._findJourneyToggleByTime(startAtMs, endAtMs)
    }

    if (!toggle) return

    const frameId = toggle.dataset.frameId
    const frame = frameId ? document.getElementById(frameId) : null
    if (!frame) return

    if (frame.classList.contains("hidden")) {
      this.toggleTrackInfo({ currentTarget: toggle })
    }

    toggle.closest(".timeline-entry")?.scrollIntoView({
      behavior: "smooth",
      block: "nearest",
    })
  }

  // Find the journey leg whose [started_at, ended_at] window overlaps the most
  // with a given epoch-ms range (a clicked route). Returns the `.journey-leg`
  // toggle so `_tryExpandPendingTrack` can open it. Journey timestamps are
  // ISO8601 with offset, so Date.parse yields a tz-safe epoch.
  _findJourneyToggleByTime(startAtMs, endAtMs) {
    const entries = this.element.querySelectorAll(
      '.timeline-entry[data-entry-type="journey"]',
    )
    let best = null
    let bestOverlap = 0
    for (const entry of entries) {
      const s = new Date(entry.dataset.startedAt).getTime()
      const e = new Date(entry.dataset.endedAt).getTime()
      if (!Number.isFinite(s) || !Number.isFinite(e)) continue
      const overlap = Math.min(e, endAtMs) - Math.max(s, startAtMs)
      if (overlap > bestOverlap) {
        bestOverlap = overlap
        best = entry
      }
    }
    return best?.querySelector(".journey-leg[data-track-id]") || null
  }

  // ---------- Period ----------
  // A day is opened without a page load: the map instance stays alive, layers
  // refetch in place, the URL updates via pushState.
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
    params.delete("month")
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

    this.syncAllDays()

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
    // A day of the period on screen is selected in place. Not on hydration
    // (alignInputs false): after a page visit the feed on screen belongs to
    // the previous period and has to be loaded anew.
    if (
      alignInputs &&
      this.selectInRange(date, { keepCamera: Boolean(this.pendingVisitId) })
    ) {
      this.selectPendingVisit()
      return
    }
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

  deselectVisit() {
    this.selectedVisitId = null
    for (const el of this.element.querySelectorAll(".visit-row--selected")) {
      el.classList.remove("visit-row--selected")
    }
    document.dispatchEvent(new CustomEvent("timeline-feed:visit-deselected"))
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

  // ---------- Filters + Search ----------
  filterChanged() {
    if (this.selectionMode) this.exitSelection()
    this.applyVisibility()
    document.dispatchEvent(
      new CustomEvent("timeline-feed:filter-changed", {
        detail: this.readFilterDetail(),
      }),
    )
  }

  // Stimulus action wired via `data-action="input->timeline-feed#search"`.
  search() {
    this.applyVisibility()
  }

  // Stimulus action on tag chips. Toggles `--active` class + aria-pressed and
  // re-applies row visibility. Multiple active chips AND together.
  toggleTag(event) {
    const btn = event.currentTarget
    const isActive = btn.classList.toggle("tag-chip--active")
    btn.setAttribute("aria-pressed", isActive ? "true" : "false")
    this.applyVisibility()
  }

  // Single source of truth — walks the rendered visit rows and toggles the
  // hidden class based on filter checkboxes, search query, and active tag chips.
  // Keeping them unified prevents the three from drifting out of sync.
  //
  // Tag semantics are OR (union) — selecting "#home" + "#gym" shows visits
  // tagged with either. AND would require visits carrying BOTH tags, which
  // doesn't match how users read "show me home AND gym visits".
  applyVisibility() {
    if (!this.hasVisitListFrameTarget) return

    const filter = this.readFilterDetail()
    const query = this.readSearchQuery()
    const activeTags = this.readActiveTags()

    const filtersActive =
      query.length > 0 ||
      activeTags.length > 0 ||
      Object.values(filter).some((v) => v === false)

    for (const day of this.visitListFrameTarget.querySelectorAll(
      ".timeline-day",
    )) {
      const rows = day.querySelectorAll(".visit-row[data-status]")
      let visibleCount = 0
      // Searching includes the normally collapsed low-confidence stops.
      day.classList.toggle("timeline-day--filtering", filtersActive)
      for (const row of rows) {
        const tokens = row.dataset.searchTokens || ""
        const statusOk = filter[row.dataset.status] !== false
        const searchOk = !query || tokens.includes(query)
        const tagsOk =
          activeTags.length === 0 || activeTags.some((t) => tokens.includes(t))
        const hidden = !(statusOk && searchOk && tagsOk)
        row.classList.toggle("visit-row--hidden", hidden)
        const collapsed =
          !filtersActive &&
          row.classList.contains("visit-row--lowconf") &&
          !day.classList.contains("timeline-day--show-lowconf")
        if (!hidden && !collapsed) visibleCount += 1
      }
      const count = day.querySelector("[data-timeline-visit-count]")
      if (count) {
        count.textContent = translate(
          filtersActive || visibleCount !== rows.length
            ? "ux_p3.timeline.filtered_count"
            : "ux_p3.timeline.visit_count",
          { count: visibleCount, total: rows.length },
        )
      }
      day
        .querySelector("[data-timeline-filter-scope]")
        ?.classList.toggle("hidden", !filtersActive)
      day
        .querySelector('[data-timeline-feed-target="emptyFiltered"]')
        ?.classList.toggle(
          "hidden",
          !(rows.length > 0 && visibleCount === 0 && filtersActive),
        )
    }
  }

  // Wired from the empty-filtered helper's "Clear search & filters" button.
  clearVisitFilters() {
    if (this.hasSearchInputTarget) {
      this.searchInputTarget.value = ""
    }
    const checkboxes = this.element.querySelectorAll(
      'input[type="checkbox"][data-status]',
    )
    for (const cb of checkboxes) {
      if (!cb.checked) cb.checked = true
    }
    const activeTagChips = this.element.querySelectorAll(
      ".tag-chip--toggle.tag-chip--active",
    )
    for (const chip of activeTagChips) {
      chip.classList.remove("tag-chip--active")
    }
    this.applyVisibility()
  }

  // Built from whatever status checkboxes exist in the DOM. With none
  // rendered (stateless visits), the empty detail filters nothing.
  readFilterDetail() {
    const detail = {}
    const checkboxes = this.element.querySelectorAll(
      'input[type="checkbox"][data-status]',
    )
    for (const cb of checkboxes) {
      detail[cb.dataset.status] = cb.checked
    }
    return detail
  }

  readSearchQuery() {
    if (!this.hasSearchInputTarget) return ""
    return (this.searchInputTarget.value || "").trim().toLowerCase()
  }

  readActiveTags() {
    return Array.from(
      this.element.querySelectorAll(".tag-chip--toggle.tag-chip--active"),
    ).map((b) => b.dataset.tagName || "")
  }

  // ---------- Day navigation ----------
  navigateDay(event) {
    const direction = event.currentTarget.dataset.direction
    // Inside a period the arrows step through its days, by the calendar
    // whatever order the days are listed in.
    const days = this.hasVisitListFrameTarget
      ? [
          ...this.visitListFrameTarget.querySelectorAll("details.timeline-day"),
        ].sort((a, b) => (a.dataset.day < b.dataset.day ? -1 : 1))
      : []
    if (days.length) {
      const step = direction === "prev" ? -1 : 1
      const next = days[days.findIndex((day) => day.open) + step]
      if (next) next.open = true
      return
    }
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

  enterSelection(event) {
    const day = event.currentTarget.closest(".timeline-day")
    if (!day) return

    if (this.selectionMode) {
      const wasSameDay = this.activeDayElement === day
      this.exitSelection()
      if (wasSameDay) return
    }

    this.selectionMode = true
    this.selectedVisitIds.clear()
    this.activeDayElement = day
    day.dataset.selectionMode = "true"

    const bar = this.activeSelectionBar()
    if (bar) bar.hidden = false
    this.syncSelectionUI()
  }

  exitSelection() {
    this.selectionMode = false
    this.selectedVisitIds.clear()

    for (const day of this.element.querySelectorAll(
      '[data-selection-mode="true"]',
    )) {
      day.removeAttribute("data-selection-mode")
    }

    for (const cb of this.rowCheckTargets) {
      cb.checked = false
    }

    const bar = this.activeSelectionBar()
    if (bar) bar.hidden = true

    this.syncSelectionUI()
    this.activeDayElement = null
  }

  toggleVisitId(id) {
    const idStr = String(id)
    if (this.selectedVisitIds.has(idStr)) {
      this.selectedVisitIds.delete(idStr)
    } else {
      this.selectedVisitIds.add(idStr)
    }
    const scope = this.activeDayElement || this.element
    const cb = scope.querySelector(
      `input[type="checkbox"][data-visit-id="${idStr}"]`,
    )
    if (cb) cb.checked = this.selectedVisitIds.has(idStr)
    this.syncSelectionUI()
  }

  rowCheckChanged(event) {
    if (!this.selectionMode) return
    const id = event.target.dataset.visitId
    if (!id) return
    if (event.target.checked) {
      this.selectedVisitIds.add(String(id))
    } else {
      this.selectedVisitIds.delete(String(id))
    }
    this.syncSelectionUI()
  }

  stopPropagation(event) {
    event.stopPropagation()
  }

  activeSelectionBar() {
    const scope = this.activeDayElement
    if (!scope) return null
    return scope.querySelector('[data-timeline-feed-target="selectionBar"]')
  }

  activeSelectionForm() {
    return this.scopedQuery('[data-timeline-feed-target="selectionForm"]')
  }

  activeSelectionCount() {
    return this.scopedQuery('[data-timeline-feed-target="selectionCount"]')
  }

  activeMergeButton() {
    return this.scopedQuery('[data-timeline-feed-target="mergeButton"]')
  }

  activeDeleteForm() {
    return this.scopedQuery('[data-timeline-feed-target="deleteForm"]')
  }

  activeDeleteButton() {
    return this.scopedQuery('[data-timeline-feed-target="deleteButton"]')
  }

  scopedQuery(selector) {
    const scope = this.activeDayElement
    if (!scope) return null
    return scope.querySelector(selector)
  }

  maxBulkVisits() {
    const bar = this.activeSelectionBar()
    const raw = bar?.dataset?.maxBulkVisits
    const n = Number.parseInt(raw, 10)
    return Number.isFinite(n) && n > 0 ? n : 500
  }

  syncSelectionUI() {
    const n = this.selectedVisitIds.size
    const max = this.maxBulkVisits()
    const overCap = n > max
    const countEl = this.activeSelectionCount()
    if (countEl) {
      countEl.textContent = overCap
        ? translate("timeline.selected_with_max", { count: n, max })
        : translate("timeline.selected", { count: n })
    }
    const mergeBtn = this.activeMergeButton()
    if (mergeBtn) {
      mergeBtn.disabled = n < 2 || overCap
      mergeBtn.textContent =
        n >= 2
          ? translate("timeline.merge_count", { count: n })
          : translate("visits.merge")
    }
    for (const [getter, key] of [
      [this.activeDeleteButton.bind(this), "common.delete"],
    ]) {
      const btn = getter()
      if (!btn) continue
      btn.disabled = n < 1 || overCap
      btn.textContent =
        n >= 1
          ? translate("timeline.action_count", {
              action: translate(key),
              count: n,
            })
          : translate(key)
    }
  }

  submitMerge(event) {
    this.submitBulkAction(event, {
      formGetter: this.activeSelectionForm.bind(this),
      buttonGetter: this.activeMergeButton.bind(this),
      minSelected: 2,
    })
  }

  submitBulkDelete(event) {
    const n = this.selectedVisitIds.size
    if (n < 1) {
      event.preventDefault()
      return
    }
    const noun = n === 1 ? "visit" : "visits"
    const message = `Delete ${n} ${noun}? Your location points stay — only the visit grouping is removed.`
    if (!window.confirm(message)) {
      event.preventDefault()
      return
    }
    this.submitBulkAction(event, {
      formGetter: this.activeDeleteForm.bind(this),
      buttonGetter: this.activeDeleteButton.bind(this),
      minSelected: 1,
    })
  }

  submitBulkAction(event, { formGetter, buttonGetter, minSelected }) {
    const form = formGetter()
    if (!form || form !== event.currentTarget) {
      event.preventDefault()
      return
    }
    if (this.selectedVisitIds.size < minSelected) {
      event.preventDefault()
      return
    }

    for (const old of form.querySelectorAll('input[name="visit_ids[]"]')) {
      old.remove()
    }
    for (const id of this.selectedVisitIds) {
      const input = document.createElement("input")
      input.type = "hidden"
      input.name = "visit_ids[]"
      input.value = id
      form.appendChild(input)
    }

    const btn = buttonGetter()
    if (btn) btn.disabled = true

    const onEnd = (e) => {
      if (e.target !== form) return
      document.removeEventListener("turbo:submit-end", onEnd)
      if (e.detail?.success) {
        this.exitSelection()
      } else {
        this.syncSelectionUI()
      }
    }
    document.addEventListener("turbo:submit-end", onEnd)
  }
}
