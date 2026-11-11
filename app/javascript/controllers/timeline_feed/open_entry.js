/**
 * Opening a visit or track from the map or the URL: pick its day, then
 * expand the matching entry once the visit list loads.
 * Mixed into TimelineFeedController; `this` is the TimelineFeedController.
 */
export const openEntry = {
  handleOpenVisit(event) {
    const { visitId, date } = event.detail || {}
    if (Number.isFinite(Number(visitId))) {
      this.pendingVisitId = Number(visitId)
    }
    if (date) this.selectDayByDate(date)
  },

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
      this._expandPendingTrackSoon()
      return
    }

    this.keepCameraOnDate = date || this.selectedDate
    if (date && date !== this.selectedDate) {
      this.navigateToDay(date, { fitBounds: false })
    } else {
      this._expandPendingTrackSoon()
    }
  },

  // The click that opens the Timeline tab also starts reloading its list, and
  // Turbo marks the frame busy only after this handler returns. One frame
  // later the reload is visible, so the track waits for the new list instead
  // of opening in the one being replaced.
  _expandPendingTrackSoon() {
    const expand = () => this._tryExpandPendingTrack()
    if (typeof requestAnimationFrame === "function")
      requestAnimationFrame(expand)
    else expand()
  },

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
  },

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
  },

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
  },

  // Expands the journey entry for `this.pendingTrackId` if it's present in
  // the currently rendered day. Idempotent — re-clicking the same track
  // collapses via `toggleTrackInfo`, but programmatic expansion only opens
  // a closed entry, never collapses an open one.
  _tryExpandPendingTrack() {
    // A reload is still on its way and will replace this list; keep the track
    // pending until the last one lands (Turbo clears busy before it renders).
    if (this.visitListFrameTarget?.hasAttribute?.("busy")) return

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
  },

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
  },
}
