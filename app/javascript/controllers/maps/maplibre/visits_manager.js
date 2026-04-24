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

  /**
   * Register document-level listeners for the timeline-feed contract.
   * See PLAN.md Task 7/8 SHARED CONTRACT.
   */
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

    this.onPlaceSelected = (e) => {
      const detail = e?.detail || {}
      const { placeId, lat, lng } = detail

      if (Number.isFinite(lat) && Number.isFinite(lng)) {
        this.controller.map?.flyTo({
          center: [lng, lat],
          zoom: 15,
          duration: 600,
        })
        return
      }

      const placesLayer = this.layerManager?.getLayer("places")
      const features = placesLayer?.data?.features || []
      const feature = features.find(
        (f) => Number(f?.properties?.id) === Number(placeId),
      )
      if (feature?.geometry?.coordinates) {
        const [flng, flat] = feature.geometry.coordinates
        if (Number.isFinite(flng) && Number.isFinite(flat)) {
          this.controller.map?.flyTo({
            center: [flng, flat],
            zoom: 15,
            duration: 600,
          })
        }
      }
    }

    this.onFilterChanged = (e) => {
      const layer = this.layerManager?.getLayer("visits")
      if (layer) layer.setStatusFilter(e?.detail || {})
    }

    this.onDaySelected = async (e) => {
      const detail = e?.detail || {}
      const { date, bounds } = detail

      // Page-level day changes now trigger a full Turbo navigation (see
      // timeline_feed_controller#navigateToDay) so the server re-renders the
      // map with the new `start_at`/`end_at` and every enabled layer refetches
      // for that day as part of normal init. The remaining case where this
      // handler fires without a full navigation is hydration after page load
      // and the `timeline:open-visit` event — in both, the map layers are
      // already aligned, so we skip the refetch. Bounds-fit still runs when a
      // day entry carries bounds (useful when another event surfaces them).
      //
      // A belt-and-braces refetch only makes sense if the map is fully ready
      // AND the rendered date range differs from the selected day — we detect
      // the second via map.style, which is undefined mid-init.
      const map = this.controller.map
      const mapReady = Boolean(map && map.isStyleLoaded && map.isStyleLoaded())

      if (date && mapReady) {
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
      "timeline-feed:place-selected",
      this.onPlaceSelected,
    )
    document.addEventListener(
      "timeline-feed:filter-changed",
      this.onFilterChanged,
    )
    document.addEventListener("timeline-feed:day-selected", this.onDaySelected)
    document.addEventListener("map:resize-needed", this.onResizeNeeded)
  }

  /**
   * Tear down document-level listeners. Not currently wired to a
   * lifecycle hook (VisitsManager is managed by the map controller),
   * but provided for future use and consistency.
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
    if (this.onPlaceSelected) {
      document.removeEventListener(
        "timeline-feed:place-selected",
        this.onPlaceSelected,
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
   * Filter visits by status
   */
  filterVisits(event) {
    const filter = event.target.value
    this.filterManager.setCurrentVisitFilter(filter)
    const searchTerm =
      document.getElementById("visits-search")?.value.toLowerCase() || ""
    const visitsLayer = this.layerManager.getLayer("visits")
    this.filterManager.filterAndUpdateVisits(searchTerm, filter, visitsLayer)
  }

  /**
   * Start create visit mode
   */
  startCreateVisit() {
    if (
      this.controller.hasSettingsPanelTarget &&
      this.controller.settingsPanelTarget.classList.contains("open")
    ) {
      this.controller.toggleSettings()
    }

    this.controller.map.getCanvas().style.cursor = "crosshair"
    Toast.info("Click on the map to place a visit")

    this.handleCreateVisitClick = (e) => {
      const { lng, lat } = e.lngLat
      this.openVisitCreationModal(lat, lng)
      this.controller.map.getCanvas().style.cursor = ""
    }

    this.controller.map.once("click", this.handleCreateVisitClick)
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

      console.log("[Maps V2] Fetched visits:", visits.length)

      this.filterManager.setAllVisits(visits)
      const visitsGeoJSON = this.dataLoader.visitsToGeoJSON(visits)

      console.log(
        "[Maps V2] Converted to GeoJSON:",
        visitsGeoJSON.features.length,
        "features",
      )

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
