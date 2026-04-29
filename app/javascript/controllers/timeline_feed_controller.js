import { Controller } from "@hotwired/stimulus"

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
    "selectionForm",
    "selectionCount",
    "mergeButton",
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
    // Also fire `visit:updated` whenever a visit row or the day frame is
    // replaced — VisitsController emits these streams on confirm / decline /
    // rename / bulk_update, and the map's visits layer needs to refetch so
    // its dot color reflects the new status.
    this.boundStreamRender = (event) => {
      const target = event?.detail?.newStream?.getAttribute?.("target") || ""
      const action = event?.detail?.newStream?.getAttribute?.("action") || ""
      const visitRowReplaced =
        action === "replace" && target.startsWith("visit_entry_")
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

  handleOpenVisit(event) {
    const { visitId, date } = event.detail || {}
    if (Number.isFinite(Number(visitId))) {
      this.pendingVisitId = Number(visitId)
    }
    if (date) this.selectDayByDate(date)
  }

  handleOpenTrack(event) {
    const { trackId, date } = event.detail || {}
    const tid = Number.parseInt(trackId, 10)
    if (!Number.isFinite(tid)) return
    this.pendingTrackId = tid

    // If the clicked track is on the already-selected day, the journey
    // entry is already rendered — expand it immediately. Otherwise navigate
    // to the day; the frame-load handler will consume pendingTrackId once the
    // new day's entries render.
    if (date && date !== this.selectedDate) {
      this.navigateToDay(date)
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
    const date = params.get("date")
    if (date) {
      const isoDate =
        date === "today" ? new Date().toLocaleDateString("en-CA") : date
      requestAnimationFrame(() => this.selectDayByDate(isoDate))
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
    const dayEl = this.visitListFrameTarget.querySelector(".timeline-day")
    if (dayEl?.dataset?.bounds) {
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

    if (this.pendingTrackId) this._tryExpandPendingTrack()

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

  // Expands the journey entry for `this.pendingTrackId` if it's present in
  // the currently rendered day. Idempotent — re-clicking the same track
  // collapses via `toggleTrackInfo`, but programmatic expansion only opens
  // a closed entry, never collapses an open one.
  _tryExpandPendingTrack() {
    const tid = this.pendingTrackId
    if (!tid) return
    this.pendingTrackId = null

    const toggle = this.element.querySelector(
      `.journey-leg[data-track-id="${tid}"]`,
    )
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

  // ---------- Calendar ----------
  // User-facing actions trigger a full Turbo navigation so the whole map
  // page (points / routes / fog-of-war / any enabled layer) rebinds to the
  // new date range — consistent with the existing top-of-page date form.
  selectDay(event) {
    const cell = event.currentTarget
    const date = cell.dataset.day
    if (!date || cell.disabled) return
    this.navigateToDay(date)
  }

  navigateToDay(date) {
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

    const params = new URLSearchParams(window.location.search)
    params.set("start_at", startAtLocal)
    params.set("end_at", endAtLocal)
    params.set("panel", "timeline")
    params.set("date", date)
    window.history.pushState({}, "", `/map/v2?${params.toString()}`)

    const startInput = document.querySelector('input[name="start_at"]')
    const endInput = document.querySelector('input[name="end_at"]')
    if (startInput) startInput.value = startAtLocal
    if (endInput) endInput.value = endAtLocal

    document.dispatchEvent(
      new CustomEvent("timeline-feed:date-navigated", {
        detail: { date, startAt: startAtLocal, endAt: endAtLocal },
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
      const start = `${date}T00:00:00Z`
      const end = `${date}T23:59:59Z`
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
  selectDayByDate(date) {
    if (this.selectionMode) this.exitSelection()
    this.applySelectedDayUI(date)

    // Tell the map — bounds are not known yet (visit list frame is async).
    // The map's visits_manager can re-center when it receives data, or listen
    // for additional events from the turbo-frame-rendered content.
    document.dispatchEvent(
      new CustomEvent("timeline-feed:day-selected", {
        detail: { date },
      }),
    )
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

    // Don't trigger when activating a nested control: rename trigger span,
    // submit button, form field, or the [data-controller="visit-name"]
    // wrapper whose click opens the inline rename form.
    if (
      event.target.closest("[data-controller='visit-name']") ||
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

    const rows = this.visitListFrameTarget.querySelectorAll("[data-status]")
    let visibleCount = 0
    for (const row of rows) {
      const tokens = row.dataset.searchTokens || ""
      const statusOk = filter[row.dataset.status] !== false
      const searchOk = !query || tokens.includes(query)
      const tagsOk =
        activeTags.length === 0 || activeTags.some((t) => tokens.includes(t))
      const hidden = !(statusOk && searchOk && tagsOk)
      row.classList.toggle("visit-row--hidden", hidden)
      if (!hidden) visibleCount += 1
    }

    // Show the "no matches — clear filters" helper only when the day has at
    // least one visit but active search/filter/tags hide them all. Prevents
    // the confusing state where the day header says "N visits" but the list
    // appears empty.
    const filtersActive =
      query.length > 0 ||
      activeTags.length > 0 ||
      Object.values(filter).some((v) => v === false)
    const shouldShowHelper =
      rows.length > 0 && visibleCount === 0 && filtersActive
    for (const el of this.emptyFilteredTargets) {
      el.classList.toggle("hidden", !shouldShowHelper)
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

  readFilterDetail() {
    const detail = { confirmed: false, suggested: false, declined: false }
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

  // ---------- Calendar month skeleton ----------
  // Paints a "neutral" version of the target month immediately on click,
  // so users see the new month structure without waiting for the
  // turbo_stream round-trip. The stream then swaps this skeleton out for
  // the real heat-colored cells the moment the response arrives.
  previewMonth(event) {
    const link = event.currentTarget
    const targetMonth = link?.dataset?.targetMonth
    if (!targetMonth) return

    const calendar = this.element.querySelector(
      '[data-testid="timeline-calendar"]',
    )
    if (!calendar) return

    const grid = calendar.querySelector(
      ".grid.grid-cols-7.gap-0\\.5:last-child",
    )
    const title = calendar.querySelector('[data-testid="calendar-title"]')
    if (!grid || !title) return

    const [yearStr, monthStr] = targetMonth.split("-")
    const year = Number.parseInt(yearStr, 10)
    const monthIdx = Number.parseInt(monthStr, 10) - 1
    if (!Number.isFinite(year) || !Number.isFinite(monthIdx)) return

    // Force English locale to match the server-rendered title
    // (`strftime('%B %Y')`) — otherwise users on a non-English browser see
    // a brief "Январь 2025" → "January 2025" flicker as the turbo_stream
    // response replaces the skeleton.
    title.textContent = new Date(year, monthIdx, 1).toLocaleDateString("en", {
      month: "long",
      year: "numeric",
    })

    // 6×7 grid, Monday-aligned — mirrors what MonthSummary builds server-side.
    const monthStart = new Date(year, monthIdx, 1)
    // Day-of-week with Monday as 0
    const offset = (monthStart.getDay() + 6) % 7
    const gridStart = new Date(year, monthIdx, 1 - offset)

    const cells = []
    for (let i = 0; i < 42; i += 1) {
      const d = new Date(gridStart)
      d.setDate(gridStart.getDate() + i)
      const inMonth = d.getMonth() === monthIdx
      const iso = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`
      const selected = iso === this.selectedDate
      const classes = [
        "cal-cell",
        "heat-0",
        "cal-cell--dark-text",
        inMonth ? null : "out-of-month",
        selected ? "cal-cell--selected" : null,
      ]
        .filter(Boolean)
        .join(" ")
      cells.push(
        `<button type="button" class="${classes}" data-day="${iso}" data-action="click->timeline-feed#selectDay" data-testid="calendar-day" disabled><span class="cal-cell__day">${d.getDate()}</span></button>`,
      )
    }

    grid.innerHTML = cells.join("")
    calendar.classList.add("timeline-calendar--loading")
  }

  // ---------- Day navigation ----------
  navigateDay(event) {
    const direction = event.currentTarget.dataset.direction
    if (!this.selectedDate) return
    // Work in UTC throughout to avoid local-timezone drift. `new Date("YYYY-MM-DDT00:00:00")`
    // is parsed as local, then toISOString() converts to UTC — which can shift
    // the date by ±1 in non-UTC timezones. Using Date.UTC + setUTCDate is stable.
    const [y, m, day] = this.selectedDate.split("-").map(Number)
    const d = new Date(Date.UTC(y, m - 1, day))
    const delta = direction === "prev" ? -1 : direction === "next" ? 1 : 0
    d.setUTCDate(d.getUTCDate() + delta)
    const newDate = d.toISOString().slice(0, 10)
    this.navigateToDay(newDate)
  }

  // ---------- Keyboard ----------
  handleKey(e) {
    if (e.target.matches?.("input, textarea, select")) return
    if (!this.element.isConnected) return

    if (e.key === "ArrowLeft") {
      this.navigateInDirection("prev")
    } else if (e.key === "ArrowRight") {
      this.navigateInDirection("next")
    }
  }

  navigateInDirection(direction) {
    if (!this.selectedDate) return
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

    const form = this.activeSelectionForm()
    if (form) form.hidden = false
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

    const form = this.activeSelectionForm()
    if (form) form.hidden = true

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

  activeSelectionForm() {
    const scope = this.activeDayElement
    if (!scope) return null
    return scope.querySelector('[data-timeline-feed-target="selectionForm"]')
  }

  activeSelectionCount() {
    const scope = this.activeDayElement
    if (!scope) return null
    return scope.querySelector('[data-timeline-feed-target="selectionCount"]')
  }

  activeMergeButton() {
    const scope = this.activeDayElement
    if (!scope) return null
    return scope.querySelector('[data-timeline-feed-target="mergeButton"]')
  }

  syncSelectionUI() {
    const n = this.selectedVisitIds.size
    const countEl = this.activeSelectionCount()
    if (countEl) {
      countEl.textContent = `${n} selected`
    }
    const mergeBtn = this.activeMergeButton()
    if (mergeBtn) {
      mergeBtn.disabled = n < 2
      mergeBtn.textContent = n >= 2 ? `Merge ${n}` : "Merge"
    }
  }

  submitMerge(event) {
    const form = this.activeSelectionForm()
    if (!form || form !== event.currentTarget) {
      event.preventDefault()
      return
    }
    if (this.selectedVisitIds.size < 2) {
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

    const mergeBtn = this.activeMergeButton()
    if (mergeBtn) mergeBtn.disabled = true

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
