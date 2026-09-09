import { translate } from "i18n"
import { Toast } from "maps_maplibre/components/toast"
import { SettingsManager } from "maps_maplibre/utils/settings_manager"

/**
 * Manages visits-related operations for Maps V2
 * Including visit creation, filtering, and layer management
 */
export class VisitsManager {
  constructor(controller) {
    this.controller = controller
    this.layerManager = controller.layerManager
    this.filterManager = controller.filterManager
    this.api = controller.api
    this.dataLoader = controller.dataLoader
    this.bindTimelineFeedListeners()
  }

  bindTimelineFeedListeners() {
    this.onVisitSelected = (e) => {
      const detail = e?.detail || {}
      const { visitId, lat, lng } = detail
      const layer = this.layerManager?.getLayer("visits")
      if (layer) layer.setSelectedVisit(visitId)
      if (Number.isFinite(lat) && Number.isFinite(lng)) {
        this.controller.map?.flyTo({
          center: [lng, lat],
          zoom: 15,
          duration: 600,
        })
      }
    }

    this.onVisitDeselected = () => {
      const layer = this.layerManager?.getLayer("visits")
      if (layer) layer.setSelectedVisit(null)
    }

    this.onFilterChanged = (e) => {
      const layer = this.layerManager?.getLayer("visits")
      if (layer) layer.setStatusFilter(e?.detail || {})
    }

    this.onDaySelected = async (e) => {
      const detail = e?.detail || {}
      const { date, bounds } = detail
      const map = this.controller.map
      const mapReady = Boolean(map?.isStyleLoaded?.())

      // Skip the per-day fetch when the day already falls inside the
      // controller's loaded date range — `loadMapData()` (triggered by
      // `timeline-feed:date-navigated`) has already fetched visits for
      // the broader range. Re-fetching causes a race where the smaller
      // request can resolve last and overwrite the larger result.
      if (date && mapReady && !this.isDayWithinLoadedRange(date)) {
        try {
          // Local day bounds (no trailing Z) to match navigateToDay and the
          // top date-range form. Using UTC here shifted the window by the tz
          // offset, so the day's visits — including the one just clicked —
          // could fall outside it and the layer got replaced with nothing.
          const startAt = `${date}T00:00:00`
          const endAt = `${date}T23:59:59`
          const visits = await this.api.fetchVisits({
            start_at: startAt,
            end_at: endAt,
          })
          const layer = this.layerManager?.getLayer("visits")
          // Don't wipe existing markers on an empty result: this refetch only
          // runs for a day the user is focusing because it contains a visit,
          // so an empty response is erroneous rather than a genuinely empty day.
          if (layer && map.isStyleLoaded() && visits.length > 0) {
            layer.update(this.dataLoader.visitsToGeoJSON(visits))
            layer.show?.()
          }
        } catch (err) {
          console.error("Failed to refetch visits for timeline day:", err)
        }
      }

      if (
        mapReady &&
        bounds &&
        Number.isFinite(bounds.sw_lat) &&
        Number.isFinite(bounds.sw_lng) &&
        Number.isFinite(bounds.ne_lat) &&
        Number.isFinite(bounds.ne_lng)
      ) {
        this.controller.map?.fitBounds(
          [
            [bounds.sw_lng, bounds.sw_lat],
            [bounds.ne_lng, bounds.ne_lat],
          ],
          { padding: 60, duration: 500 },
        )
      }
    }

    this.onResizeNeeded = () => {
      this.controller.map?.resize()
    }

    document.addEventListener(
      "timeline-feed:visit-selected",
      this.onVisitSelected,
    )
    document.addEventListener(
      "timeline-feed:visit-deselected",
      this.onVisitDeselected,
    )
    document.addEventListener(
      "timeline-feed:filter-changed",
      this.onFilterChanged,
    )
    document.addEventListener("timeline-feed:day-selected", this.onDaySelected)
    document.addEventListener("map:resize-needed", this.onResizeNeeded)
  }

  /**
   * Returns true when `date` (YYYY-MM-DD) falls inside the controller's
   * currently-loaded date range. Used to skip redundant per-day fetches
   * after a broader fetch has already covered the day.
   */
  isDayWithinLoadedRange(date) {
    const start = this.controller.startDateValue
    const end = this.controller.endDateValue
    if (!start || !end || !date) return false
    return date >= start.slice(0, 10) && date <= end.slice(0, 10)
  }

  /**
   * Tear down document-level listeners. Wired into the map controller's
   * `disconnect()` so Turbo navigation away from `/map/v2` stops dead
   * handlers from firing on a removed map.
   */
  destroy() {
    if (this.onVisitSelected) {
      document.removeEventListener(
        "timeline-feed:visit-selected",
        this.onVisitSelected,
      )
    }
    if (this.onVisitDeselected) {
      document.removeEventListener(
        "timeline-feed:visit-deselected",
        this.onVisitDeselected,
      )
    }
    if (this.onFilterChanged) {
      document.removeEventListener(
        "timeline-feed:filter-changed",
        this.onFilterChanged,
      )
    }
    if (this.onDaySelected) {
      document.removeEventListener(
        "timeline-feed:day-selected",
        this.onDaySelected,
      )
    }
    if (this.onResizeNeeded) {
      document.removeEventListener("map:resize-needed", this.onResizeNeeded)
    }
    this.detachViewportRefetch()
    this.disarmCreateVisit()
  }

  /**
   * Toggle visits layer
   * Fetches visits from backend on first enable (lazy-load pattern).
   * Fetches are bounded to the current map viewport — see refetchInViewport.
   */
  async toggleVisits(event) {
    const enabled = event.target.checked
    SettingsManager.updateSetting("visitsEnabled", enabled)

    const visitsLayer = this.layerManager.getLayer("visits")
    if (!visitsLayer) return

    if (enabled) {
      try {
        if (!visitsLayer.data?.features?.length) {
          this.controller.showProgress()
          this.controller.updateLoadingCounts({
            counts: { visits: 0 },
            isComplete: false,
          })

          const visits = await this.fetchVisitsForCurrentViewport()
          this.filterManager.setAllVisits(visits)
          visitsLayer.update(this.dataLoader.visitsToGeoJSON(visits))

          this.controller.updateLoadingCounts({
            counts: { visits: visits.length },
            isComplete: true,
          })
        }
        visitsLayer.show()
        if (this.controller.hasVisitsSearchTarget) {
          this.controller.visitsSearchTarget.style.display = "block"
        }
        this.attachViewportRefetch()
      } catch (error) {
        console.error("Failed to toggle visits layer:", error)
        this.controller.hideProgress()
      }
    } else {
      visitsLayer.hide()
      if (this.controller.hasVisitsSearchTarget) {
        this.controller.visitsSearchTarget.style.display = "none"
      }
      this.detachViewportRefetch()
    }
  }

  /**
   * Build viewport bounds from the live map. Returned shape matches the
   * keys fetchVisits / fetchVisitsPage expect; returns an empty object
   * when the map isn't ready so callers can spread it safely.
   */
  currentViewportBounds() {
    const map = this.controller.map
    if (!map?.getBounds) return {}
    const b = map.getBounds()
    const swLng = b.getWest()
    const neLng = b.getEast()

    // When zoomed out far enough to see the whole world — or far enough that
    // getBounds() wraps the antimeridian and returns west >= east — a bbox is
    // meaningless. Sending it builds an inverted ST_MakeEnvelope server-side
    // that matches nothing, so every visit marker vanishes on zoom-out.
    // Drop the bounds entirely; fetchVisits then returns all visits in range.
    if (neLng - swLng >= 360 || swLng >= neLng) return {}

    // Clamp to valid lat/lng so the server envelope stays well-formed.
    return {
      sw_lat: Math.max(b.getSouth(), -90),
      sw_lng: Math.max(swLng, -180),
      ne_lat: Math.min(b.getNorth(), 90),
      ne_lng: Math.min(neLng, 180),
    }
  }

  /**
   * Wrapper that always passes the current map viewport. Used both for
   * the initial toggle-on fetch and for pan/zoom refetches.
   */
  async fetchVisitsForCurrentViewport() {
    return this.api.fetchVisits({
      start_at: this.controller.startDateValue,
      end_at: this.controller.endDateValue,
      ...this.currentViewportBounds(),
    })
  }

  /**
   * Refetch visits for the current viewport and replace the layer's data.
   * Debounced via moveend timer — see attachViewportRefetch.
   */
  async refetchVisitsForViewport() {
    const visitsLayer = this.layerManager.getLayer("visits")
    if (!visitsLayer || !visitsLayer.visible) return
    try {
      const visits = await this.fetchVisitsForCurrentViewport()
      this.filterManager.setAllVisits(visits)
      visitsLayer.update(this.dataLoader.visitsToGeoJSON(visits))
    } catch (error) {
      console.error("[Maps V2] Viewport visit refetch failed:", error)
    }
  }

  attachViewportRefetch() {
    if (this._viewportListenerAttached) return
    const map = this.controller.map
    if (!map?.on) return

    this._onViewportMoveEnd = () => {
      if (this._viewportRefetchTimer) clearTimeout(this._viewportRefetchTimer)
      this._viewportRefetchTimer = setTimeout(
        () => this.refetchVisitsForViewport(),
        400,
      )
    }
    map.on("moveend", this._onViewportMoveEnd)
    this._viewportListenerAttached = true
  }

  detachViewportRefetch() {
    if (!this._viewportListenerAttached) return
    if (this._viewportRefetchTimer) {
      clearTimeout(this._viewportRefetchTimer)
      this._viewportRefetchTimer = null
    }
    const map = this.controller.map
    if (map?.off && this._onViewportMoveEnd) {
      map.off("moveend", this._onViewportMoveEnd)
    }
    this._onViewportMoveEnd = null
    this._viewportListenerAttached = false
  }

  /**
   * Search visits
   */
  searchVisits(event) {
    const searchTerm = event.target.value.toLowerCase()
    const visitsLayer = this.layerManager.getLayer("visits")
    this.filterManager.filterAndUpdateVisits(
      searchTerm,
      this.filterManager.getCurrentVisitFilter(),
      visitsLayer,
    )
  }

  /**
   * Filter visits by status. Reads the search term from the controller's
   * visitsSearch target (a container) instead of document.getElementById
   * so we don't reach across the DOM by id.
   */
  filterVisits(event) {
    const filter = event.target.value
    this.filterManager.setCurrentVisitFilter(filter)
    const searchInput = this.controller.hasVisitsSearchTarget
      ? this.controller.visitsSearchTarget.querySelector('input[type="text"]')
      : null
    const searchTerm = searchInput?.value.toLowerCase() || ""
    const visitsLayer = this.layerManager.getLayer("visits")
    this.filterManager.filterAndUpdateVisits(searchTerm, filter, visitsLayer)
  }

  /**
   * Start create visit mode. Idempotent: re-entering disarms any
   * previously-armed click handler so we don't fire multiple modals.
   * Esc disarms without creating.
   */
  startCreateVisit() {
    this.disarmCreateVisit()

    this.controller.map.getCanvas().style.cursor = "crosshair"
    Toast.info(translate("messages.click_on_the_map_to_place_a_visit_esc_to"))

    this.handleCreateVisitClick = (e) => {
      const { lng, lat } = e.lngLat
      this.disarmCreateVisit()
      this.openVisitCreationModal(lat, lng)
    }

    this.handleCreateVisitEscape = (e) => {
      if (e.key === "Escape") this.disarmCreateVisit()
    }

    this.controller.map.once("click", this.handleCreateVisitClick)
    document.addEventListener("keydown", this.handleCreateVisitEscape)
    this.createVisitArmed = true
  }

  disarmCreateVisit() {
    if (!this.createVisitArmed) return

    if (this.handleCreateVisitClick) {
      this.controller.map?.off("click", this.handleCreateVisitClick)
      this.handleCreateVisitClick = null
    }
    if (this.handleCreateVisitEscape) {
      document.removeEventListener("keydown", this.handleCreateVisitEscape)
      this.handleCreateVisitEscape = null
    }
    if (this.controller.map?.getCanvas) {
      this.controller.map.getCanvas().style.cursor = ""
    }
    this.createVisitArmed = false
  }

  /**
   * Open visit creation modal
   */
  openVisitCreationModal(lat, lng) {
    const modalElement = document.querySelector(
      '[data-controller="visit-creation-v2"]',
    )

    if (!modalElement) {
      Toast.error(translate("messages.visit_creation_modal_not_available"))
      return
    }

    const controller =
      this.controller.application.getControllerForElementAndIdentifier(
        modalElement,
        "visit-creation-v2",
      )

    if (controller) {
      controller.open(lat, lng, this.controller)
    } else {
      Toast.error(translate("messages.visit_creation_controller_not_available"))
    }
  }

  /**
   * Handle visit creation event - reload visits, update layer, and
   * enable the Visits layer so the new visit is immediately visible.
   * Without auto-enabling, users would create a visit and see nothing
   * on the map because the layer toggle was off.
   */
  async handleVisitCreated(event) {
    try {
      const visitsLayer = this.layerManager.getLayer("visits")
      if (!visitsLayer) {
        console.warn("[Maps V2] Visits layer not found, cannot update")
        return
      }

      const visit = event?.detail?.visit
      let visits
      if (visit && this.filterManager.allVisits?.length) {
        // Layer already populated — append/replace this visit locally instead
        // of re-pulling the whole viewport from the backend.
        visits = this._upsertVisit(this.filterManager.allVisits, visit)
      } else {
        // Initial load: fetch the viewport set once, then make sure the
        // just-saved visit is included even if it falls outside the current
        // date range or viewport bounds (otherwise its marker never appears).
        const fetched = await this.fetchVisitsForCurrentViewport()
        visits = visit ? this._upsertVisit(fetched, visit) : fetched
      }

      this.filterManager.setAllVisits(visits)
      visitsLayer.update(this.dataLoader.visitsToGeoJSON(visits))

      this._ensureVisitsVisible(visitsLayer)
      this.attachViewportRefetch()
    } catch (error) {
      console.error("[Maps V2] Failed to update visits:", error)
    }
  }

  /**
   * Handle visit update event - same upsert path as creation.
   */
  async handleVisitUpdated(event) {
    await this.handleVisitCreated(event)
  }

  /**
   * Append or replace a visit in a list by id, returning a new array.
   * @private
   */
  _upsertVisit(visits, visit) {
    const list = visits || []
    const index = list.findIndex((v) => v.id === visit.id)
    return index >= 0
      ? list.map((v, i) => (i === index ? visit : v))
      : [...list, visit]
  }

  /**
   * Show and enable the Visits layer. Without this, creating a visit while the
   * layer toggle is off would leave the new marker in a hidden layer.
   * @private
   */
  _ensureVisitsVisible(visitsLayer) {
    visitsLayer.show()
    SettingsManager.updateSetting("visitsEnabled", true)

    const toggle = document.querySelector(
      '[data-maps--maplibre-target="visitsToggle"]',
    )
    if (toggle) toggle.checked = true

    if (this.controller.hasVisitsSearchTarget) {
      this.controller.visitsSearchTarget.style.display = "block"
    }
  }
}
