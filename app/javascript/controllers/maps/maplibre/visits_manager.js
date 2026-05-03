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
          const startAt = `${date}T00:00:00Z`
          const endAt = `${date}T23:59:59Z`
          const visits = await this.api.fetchVisits({
            start_at: startAt,
            end_at: endAt,
          })
          const layer = this.layerManager?.getLayer("visits")
          if (layer && map.isStyleLoaded()) {
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
    this.disarmCreateVisit()
  }

  /**
   * Toggle visits layer
   * Fetches visits from backend on first enable (lazy-load pattern)
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

          const visits = await this.api.fetchVisits({
            start_at: this.controller.startDateValue,
            end_at: this.controller.endDateValue,
          })
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
      } catch (error) {
        console.error("Failed to toggle visits layer:", error)
        this.controller.hideProgress()
      }
    } else {
      visitsLayer.hide()
      if (this.controller.hasVisitsSearchTarget) {
        this.controller.visitsSearchTarget.style.display = "none"
      }
    }
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
    if (
      this.controller.hasSettingsPanelTarget &&
      this.controller.settingsPanelTarget.classList.contains("open")
    ) {
      this.controller.toggleSettings()
    }

    this.disarmCreateVisit()

    this.controller.map.getCanvas().style.cursor = "crosshair"
    Toast.info("Click on the map to place a visit (Esc to cancel)")

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
      Toast.error("Visit creation modal not available")
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
      Toast.error("Visit creation controller not available")
    }
  }

  /**
   * Handle visit creation event - reload visits and update layer
   */
  async handleVisitCreated(_event) {
    try {
      const visits = await this.api.fetchVisits({
        start_at: this.controller.startDateValue,
        end_at: this.controller.endDateValue,
      })

      this.filterManager.setAllVisits(visits)
      const visitsGeoJSON = this.dataLoader.visitsToGeoJSON(visits)

      const visitsLayer = this.layerManager.getLayer("visits")
      if (visitsLayer) {
        visitsLayer.update(visitsGeoJSON)
      } else {
        console.warn("[Maps V2] Visits layer not found, cannot update")
      }
    } catch (error) {
      console.error("[Maps V2] Failed to reload visits:", error)
    }
  }

  /**
   * Handle visit update event - reload visits and update layer
   */
  async handleVisitUpdated(event) {
    await this.handleVisitCreated(event)
  }
}
