import { Controller } from "@hotwired/stimulus"

/**
 * Timeline Feed Controller (Unified Timeline)
 *
 * Coordinates the Timeline tab's calendar, visit list, filters, and place drawer,
 * and dispatches events the MapLibre layer listens for.
 *
 * See docs/specs for contract details — event names and DOM attributes must match
 * what the views (Task 5), CSS (Task 6), and MapLibre layer/manager (Task 8) emit/expect.
 */
export default class extends Controller {
  static targets = ["visitListFrame", "scopeBadge", "searchInput"]

  connect() {
    this.selectedDate = null
    this.selectedVisitId = null
    // When the visit list turbo-frame finishes loading, apply any pending
    // `visit_id=` URL-param selection (hydration is async because the frame
    // lazy-loads per-day data).
    this.pendingVisitId = null

    this.boundKeyHandler = this.handleKey.bind(this)
    document.addEventListener("keydown", this.boundKeyHandler)

    // Clicking a visit pin on the map dispatches `timeline:open-visit`
    // (see event_handlers.js#handleVisitClick). Jump to the day and queue
    // the visit for halo selection.
    this.boundOpenVisit = this.handleOpenVisit.bind(this)
    document.addEventListener("timeline:open-visit", this.boundOpenVisit)

    if (this.hasVisitListFrameTarget) {
      this.boundFrameLoad = this.handleVisitFrameLoad.bind(this)
      this.visitListFrameTarget.addEventListener(
        "turbo:frame-load",
        this.boundFrameLoad,
      )
    }

    // Re-apply filter + search visibility after any turbo_stream update
    // (e.g., VisitsController#update replaces the row with fresh state, and
    // without this the newly-rendered row wouldn't honor the active filters).
    this.boundStreamRender = () =>
      requestAnimationFrame(() => this.applyVisibility())
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

    // Place drawer
    const placeId = params.get("place_id")
    if (placeId) {
      const parsed = Number.parseInt(placeId, 10)
      if (Number.isFinite(parsed)) {
        requestAnimationFrame(() => this.openDrawerForPlace(parsed))
      }
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
    if (cell) cell.classList.add("cal-cell--selected")

    if (this.hasVisitListFrameTarget) {
      const start = `${date}T00:00:00Z`
      const end = `${date}T23:59:59Z`
      this.visitListFrameTarget.src = `/map/timeline_feeds?start_at=${encodeURIComponent(
        start,
      )}&end_at=${encodeURIComponent(end)}`
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
    // Don't trigger when activating a nested control: drawer button, rename
    // trigger span, submit button, form field, or the [data-controller="visit-name"]
    // wrapper whose click opens the inline rename form.
    if (
      event.target.closest("[data-action*='openPlaceDrawer']") ||
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
    const { entryType, startedAt, endedAt, trackId } = el.dataset
    if (!startedAt || !endedAt) return
    document.dispatchEvent(
      new CustomEvent("timeline-feed:entry-hover", {
        detail: { entryType, startedAt, endedAt, trackId },
      }),
    )
  }

  entryUnhover() {
    document.dispatchEvent(new CustomEvent("timeline-feed:entry-unhover"))
  }

  // ---------- Place drawer ----------
  openPlaceDrawer(event) {
    event.stopPropagation()
    const button = event.currentTarget
    const placeId = Number.parseInt(button.dataset.placeId, 10)
    if (!Number.isFinite(placeId)) return
    this.openDrawerForPlace(placeId)
  }

  openDrawerForPlace(placeId) {
    const drawer = this.ensureDrawerElement()
    drawer.src = `/places/${placeId}`
    drawer.classList.add("place-drawer--open")

    document.dispatchEvent(
      new CustomEvent("timeline-feed:place-selected", {
        detail: { placeId },
      }),
    )
  }

  closePlaceDrawer() {
    const drawer = document.getElementById("place-drawer")
    if (drawer) drawer.classList.remove("place-drawer--open")
  }

  ensureDrawerElement() {
    let drawer = document.getElementById("place-drawer")
    if (drawer) return drawer

    drawer = document.createElement("turbo-frame")
    drawer.id = "place-drawer"
    drawer.className = "place-drawer"
    drawer.setAttribute("data-testid", "place-drawer")

    const closeBtn = document.createElement("button")
    closeBtn.type = "button"
    closeBtn.className =
      "btn btn-sm btn-ghost btn-circle absolute top-2 right-2 z-10"
    closeBtn.setAttribute(
      "data-action",
      "click->timeline-feed#closePlaceDrawer",
    )
    closeBtn.setAttribute("data-testid", "place-drawer-close")
    closeBtn.textContent = "✕"
    drawer.appendChild(closeBtn)

    const container = document.querySelector(".maps-maplibre-container")
    if (container) {
      container.appendChild(drawer)
    } else {
      document.body.appendChild(drawer)
    }

    return drawer
  }

  // ---------- Filters + Search ----------
  filterChanged() {
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
    for (const row of rows) {
      const tokens = row.dataset.searchTokens || ""
      const statusOk = filter[row.dataset.status] !== false
      const searchOk = !query || tokens.includes(query)
      const tagsOk =
        activeTags.length === 0 || activeTags.some((t) => tokens.includes(t))
      row.classList.toggle(
        "visit-row--hidden",
        !(statusOk && searchOk && tagsOk),
      )
    }
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

    if (e.key === "Escape") {
      this.closePlaceDrawer()
    } else if (e.key === "ArrowLeft") {
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
}
