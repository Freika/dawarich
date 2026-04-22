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
  static targets = ["visitListFrame", "daySummary", "scopeBadge"]

  connect() {
    this.selectedDate = null
    this.selectedVisitId = null

    this.boundKeyHandler = this.handleKey.bind(this)
    document.addEventListener("keydown", this.boundKeyHandler)

    // URL params may drive initial day/status/place selection
    this.hydrateFromUrl()
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundKeyHandler)
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
      this.dispatchFilterChange()
    }

    // Date selection
    const date = params.get("date")
    if (date) {
      const isoDate =
        date === "today" ? new Date().toISOString().slice(0, 10) : date
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
  }

  // ---------- Calendar ----------
  selectDay(event) {
    const cell = event.currentTarget
    const date = cell.dataset.day
    if (!date || cell.disabled) return
    this.selectDayByDate(date)
  }

  selectDayByDate(date) {
    this.selectedDate = date

    // Visual selection on calendar
    for (const el of this.element.querySelectorAll(".cal-cell--selected")) {
      el.classList.remove("cal-cell--selected")
    }
    const cell = this.element.querySelector(`[data-day="${date}"]`)
    if (cell) cell.classList.add("cal-cell--selected")

    // Update the visit list turbo frame to fetch this day's feed
    if (this.hasVisitListFrameTarget) {
      const start = `${date}T00:00:00Z`
      const end = `${date}T23:59:59Z`
      this.visitListFrameTarget.src = `/map/timeline_feeds?start_at=${encodeURIComponent(
        start,
      )}&end_at=${encodeURIComponent(end)}`
    }

    // Update scope badge text
    if (this.hasScopeBadgeTarget) {
      const d = new Date(`${date}T00:00:00`)
      const label = d.toLocaleDateString(undefined, {
        weekday: "short",
        month: "short",
        day: "numeric",
      })
      this.scopeBadgeTarget.textContent = label
    }

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
    // Don't trigger when clicking a nested place button / form / input
    if (
      event.target.closest("[data-action*='openPlaceDrawer']") ||
      event.target.closest("button[type='submit']") ||
      event.target.closest("input") ||
      event.target.closest("form")
    ) {
      return
    }

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

  // ---------- Filters ----------
  filterChanged() {
    this.dispatchFilterChange()
  }

  dispatchFilterChange() {
    const checkboxes = this.element.querySelectorAll(
      'input[type="checkbox"][data-status]',
    )
    const detail = { confirmed: false, suggested: false, declined: false }
    for (const cb of checkboxes) {
      detail[cb.dataset.status] = cb.checked
    }

    document.dispatchEvent(
      new CustomEvent("timeline-feed:filter-changed", { detail }),
    )
  }

  // ---------- Day navigation ----------
  navigateDay(event) {
    const direction = event.currentTarget.dataset.direction
    if (!this.selectedDate) return
    const d = new Date(`${this.selectedDate}T00:00:00`)
    if (direction === "prev") d.setDate(d.getDate() - 1)
    if (direction === "next") d.setDate(d.getDate() + 1)
    const newDate = d.toISOString().slice(0, 10)
    this.selectDayByDate(newDate)
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
