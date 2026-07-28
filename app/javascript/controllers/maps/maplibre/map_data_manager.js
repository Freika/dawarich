import maplibregl from "maplibre-gl"
import { Toast } from "maps_maplibre/components/toast"
import { UpgradeBanner } from "maps_maplibre/components/upgrade_banner"
import {
  flightWindows,
  maskLines,
  maskPoints,
} from "maps_maplibre/utils/flight_mask"
import { trimOutlierCoords } from "maps_maplibre/utils/geometry"
import { isGatedPlan } from "maps_maplibre/utils/layer_gate"
import { performanceMonitor } from "maps_maplibre/utils/performance_monitor"

const EMPTY_GEOJSON = { type: "FeatureCollection", features: [] }

/**
 * Manages data loading and layer setup for the map
 */
export class MapDataManager {
  constructor(controller) {
    this.controller = controller
    this.map = controller.map
    this.dataLoader = controller.dataLoader
    this.layerManager = controller.layerManager
    this.filterManager = controller.filterManager
    this.eventHandlers = controller.eventHandlers
  }

  /**
   * Load map data from API and setup layers
   * Initializes empty layers first for z-ordering, then updates them
   * incrementally as each data source completes.
   * @param {string} startDate - Start date for data range
   * @param {string} endDate - End date for data range
   * @param {Object} options - Loading options
   */
  async loadMapData(startDate, endDate, options = {}) {
    const { showLoading = true, fitBounds = true } = options
    this._hasFittedBounds = false

    performanceMonitor.mark("load-map-data")

    if (showLoading) {
      this.controller.showProgress()
    }

    // Hoisted out of `try` so the `finally` block can await background
    // work (tracks / photos) before deciding whether to dismiss the badge.
    let data = null

    try {
      // 1. Initialize all layers with empty data for correct z-ordering
      await this._setupLayers({
        pointsGeoJSON: EMPTY_GEOJSON,
        routesGeoJSON: EMPTY_GEOJSON,
        visitsGeoJSON: EMPTY_GEOJSON,
        photosGeoJSON: EMPTY_GEOJSON,
        areasGeoJSON: EMPTY_GEOJSON,
        tracksGeoJSON: EMPTY_GEOJSON,
        placesGeoJSON: EMPTY_GEOJSON,
      })

      // Visits load is windowed to the current map viewport. On first
      // load `getBounds()` may not have settled yet — fall back to an
      // unbounded fetch in that case so we don't drop visits silently.
      const map = this.controller?.map
      let viewportBounds
      if (map?.getBounds) {
        const b = map.getBounds()
        viewportBounds = {
          sw_lat: b.getSouth(),
          sw_lng: b.getWest(),
          ne_lat: b.getNorth(),
          ne_lng: b.getEast(),
        }
      }

      // 2. Fetch data with incremental callbacks
      data = await this.dataLoader.fetchMapData(startDate, endDate, {
        viewportBounds,
        onUpdate: showLoading
          ? (info) => this.controller.updateLoadingCounts(info)
          : null,
        onLayerData: (source, geoJSON) =>
          this._updateLayerBySource(source, geoJSON),
        onTracksLoaded: (tracksGeoJSON) => {
          console.log(
            "[MapDataManager] Updating tracks layer from background load",
          )
          this._updateTracksLayer(tracksGeoJSON)
          // Tracks usually have the largest bbox of any layer (they include
          // every leg between visits), so when they arrive late we re-fit to
          // them — but if an earlier fit already covers them we skip the
          // pointless blink, and otherwise ease rather than snap so the late
          // correction reads as intentional. skipIfCovered only applies
          // after a real fit: the initial world view trivially "covers"
          // everything and must not suppress the only fit.
          if (fitBounds && tracksGeoJSON?.features?.length) {
            this._fitMapToBounds(tracksGeoJSON, {
              skipIfCovered: this._hasFittedBounds,
              animate: this._hasFittedBounds,
            })
            this._hasFittedBounds = true
          }
        },
        onPhotosLoaded: (photosGeoJSON) => {
          console.log(
            "[MapDataManager] Updating photos layer from background load",
          )
          this._updatePhotosLayer(photosGeoJSON)
        },
      })

      // 3. Store visits for filtering
      this.filterManager.setAllVisits(data.visits)

      // 4. Store data for replay and other features
      this.lastLoadedData = data

      // 5. Show upsell banner for Lite users when searching outside the 12-month window
      if (isGatedPlan(this.controller.userPlanValue)) {
        this._showDataWindowBanner()
      }

      // 6. Fit bounds if requested — use the first available data source.
      // Skipped when the tracks background fetch already fitted (it can
      // land first on fast responses) so we never fit twice.
      if (fitBounds && !this._hasFittedBounds) {
        this._hasFittedBounds = this._fitToFirstAvailable([
          data.pointsGeoJSON,
          data.routesGeoJSON,
          data.visitsGeoJSON,
        ])
      }

      // 7. Reload hexagons if currently visible — they own their own fetch
      // pipeline (raw points + h3 aggregation), so they need a date-range
      // reload separate from the main data flow.
      const hexagonLayer = this.layerManager.getLayer("hexagons")
      if (hexagonLayer?.visible) {
        hexagonLayer
          .reload({ start_at: startDate, end_at: endDate })
          .catch((error) => {
            console.error("[MapDataManager] Hexagon reload failed:", error)
          })
      }

      // 8. Reload fog hexagons if fog is visible in hexagon mode — same
      // reasoning: they own their own fetch pipeline.
      const fogLayer = this.layerManager.getLayer("fog")
      if (fogLayer?.visible && fogLayer.mode === "hexagons") {
        fogLayer.reloadHexagons()
      }

      return data
    } catch (error) {
      console.error("[MapDataManager] Failed to load map data:", error)
      if (showLoading) {
        this.controller.hideProgress()
      }
      Toast.error("Failed to load location data. Please try again.")
      throw error
    } finally {
      const duration = performanceMonitor.measure("load-map-data")
      console.log(`[Performance] Map data loaded in ${duration}ms`)

      // Wait for background fetches (tracks, photos) to finish before
      // running the safety net. If we don't, the badge gets force-hidden
      // while tracks are still loading — see issue: "loader disappears
      // before tracks are rendered."
      if (data?.backgroundReady) {
        try {
          await data.backgroundReady
        } catch {
          /* allSettled never rejects but be defensive */
        }
      }

      // Safety net: if the counter didn't complete (e.g. no sources expected,
      // or the user has every layer disabled), ensure the badge is dismissed
      // after a short delay so it doesn't linger forever.
      if (showLoading && this.controller.hasProgressBadgeTarget) {
        const badge = this.controller.progressBadgeTarget
        if (
          badge.classList.contains("visible") &&
          !badge.classList.contains("complete")
        ) {
          badge.classList.add("complete")
          setTimeout(() => this.controller.hideProgress(), 800)
        }
      }
    }
  }

  /**
   * Ensure points data is loaded (lazy-load for point-dependent layers).
   * Deduplicates concurrent calls via a shared promise.
   */
  async ensurePointsLoaded() {
    if (this.lastLoadedData?.points?.length > 0) return
    if (!this._pointsLoadPromise) {
      this._pointsLoadPromise = this._loadPoints()
    }
    return this._pointsLoadPromise
  }

  /**
   * Fetch points data, cache it, and update all 5 point-dependent layers.
   * @private
   */
  async _loadPoints() {
    try {
      this.controller.showProgress()
      this.controller.updateLoadingCounts({
        counts: { points: 0 },
        isComplete: false,
      })

      const {
        points,
        pointsGeoJSON,
        allPointsGeoJSON,
        routesGeoJSON,
        routesBaseGeoJSON,
      } = await this.dataLoader.fetchPointsData(
        this.controller.startDateValue,
        this.controller.endDateValue,
      )

      if (!this.lastLoadedData) this.lastLoadedData = {}
      this.lastLoadedData.points = points
      this.lastLoadedData.pointsGeoJSON = pointsGeoJSON
      this.lastLoadedData.routesGeoJSON = routesGeoJSON
      this.lastLoadedData.routesBaseGeoJSON = routesBaseGeoJSON

      this._updateLayerBySource("points", pointsGeoJSON)
      // Heatmap, fog and scratch need all points
      this._updateLayerBySource("heatmap", allPointsGeoJSON)
      this._updateLayerBySource("routes", routesGeoJSON)
      this._updateLayerBySource("routes-base", routesBaseGeoJSON)
      this._updateLayerBySource("fog", allPointsGeoJSON)
      this._updateLayerBySource("scratch", allPointsGeoJSON)

      this.controller.updateLoadingCounts({
        counts: { points: points.length },
        isComplete: true,
      })
    } finally {
      this._pointsLoadPromise = null
      this.controller.hideProgress()
    }
  }

  /**
   * Update a specific layer by source name
   * @private
   */
  _updateLayerBySource(source, geoJSON) {
    // Handle routes-base separately — it updates the routes layer's base source
    if (source === "routes-base") {
      const routesLayer = this.layerManager?.getLayer("routes")
      if (routesLayer?.updateBaseData) {
        routesLayer.updateBaseData(geoJSON)
      }
      return
    }

    const layerMap = {
      points: "points",
      heatmap: "heatmap",
      routes: "routes",
      visits: "visits",
      areas: "areas",
      places: "places",
      tracks: "tracks",
      photos: "photos",
      fog: "fog",
      scratch: "scratch",
      flights: "flights",
    }
    const layerName = layerMap[source]
    if (!layerName) return

    const layer = this.layerManager?.getLayer(layerName)
    if (layer) {
      layer.update(geoJSON)
    }

    if (source === "flights") {
      this.applyFlightMask()
    }
  }

  /**
   * Give AirTrail flights render priority: when the Flights layer is visible,
   * hide GPS points/routes/tracks that fall inside a flight's time window.
   * When hidden, restore the original (unmasked) GPS geometry. Reversible.
   */
  applyFlightMask() {
    const flightsLayer = this.layerManager?.getLayer("flights")
    const data = this.lastLoadedData
    if (!data) return

    const pointsLayer = this.layerManager?.getLayer("points")
    const routesLayer = this.layerManager?.getLayer("routes")
    const tracksLayer = this.layerManager?.getLayer("tracks")

    const windows = flightsLayer?.visible
      ? flightWindows(data.flightsGeoJSON)
      : []

    if (windows.length === 0) {
      pointsLayer?.update(data.pointsGeoJSON || EMPTY_GEOJSON)
      routesLayer?.update(data.routesGeoJSON || EMPTY_GEOJSON)
      if (data.tracksGeoJSON) tracksLayer?.update(data.tracksGeoJSON)
      return
    }

    pointsLayer?.update(
      maskPoints(data.pointsGeoJSON || EMPTY_GEOJSON, windows),
    )
    routesLayer?.update(maskLines(data.routesGeoJSON || EMPTY_GEOJSON, windows))
    if (data.tracksGeoJSON) {
      tracksLayer?.update(maskLines(data.tracksGeoJSON, windows))
    }
  }

  /**
   * Update tracks layer after background load completes
   * @private
   */
  _updateTracksLayer(tracksGeoJSON) {
    const tracksLayer = this.layerManager?.getLayer("tracks")
    if (tracksLayer) {
      tracksLayer.update(tracksGeoJSON)
      if (this.lastLoadedData) {
        this.lastLoadedData.tracksGeoJSON = tracksGeoJSON
      }
    }
  }

  /**
   * Update photos layer after background load completes
   * @private
   */
  _updatePhotosLayer(photosGeoJSON) {
    const photosLayer = this.layerManager?.getLayer("photos")
    if (photosLayer) {
      photosLayer.update(photosGeoJSON)
      if (this.lastLoadedData) {
        this.lastLoadedData.photosGeoJSON = photosGeoJSON
      }
    }
  }

  /**
   * Setup all map layers with loaded data
   * @private
   */
  async _setupLayers(data) {
    const addAllLayers = async () => {
      await this.layerManager.addAllLayers(
        data.pointsGeoJSON,
        data.routesGeoJSON,
        data.visitsGeoJSON,
        data.photosGeoJSON,
        data.areasGeoJSON,
        data.tracksGeoJSON,
        data.placesGeoJSON,
        data.flightsGeoJSON,
      )

      // Setup event handlers after layers are added
      this.layerManager.setupLayerEventHandlers({
        handlePointClick: this.eventHandlers.handlePointClick.bind(
          this.eventHandlers,
        ),
        handleVisitClick: this.eventHandlers.handleVisitClick.bind(
          this.eventHandlers,
        ),
        handlePhotoClick: this.eventHandlers.handlePhotoClick.bind(
          this.eventHandlers,
        ),
        handlePlaceClick: this.eventHandlers.handlePlaceClick.bind(
          this.eventHandlers,
        ),
        handleAreaClick: this.eventHandlers.handleAreaClick.bind(
          this.eventHandlers,
        ),
        handleAnomalyClick: this.eventHandlers.handleAnomalyClick.bind(
          this.eventHandlers,
        ),
        handleRouteClick: this.eventHandlers.handleRouteClick.bind(
          this.eventHandlers,
        ),
        handleRouteHover: this.eventHandlers.handleRouteHover.bind(
          this.eventHandlers,
        ),
        handleRouteMouseLeave: this.eventHandlers.handleRouteMouseLeave.bind(
          this.eventHandlers,
        ),
        clearRouteSelection: this.eventHandlers.clearRouteSelection.bind(
          this.eventHandlers,
        ),
        handleTrackClick: this.eventHandlers.handleTrackClick.bind(
          this.eventHandlers,
        ),
        clearTrackSelection: this.eventHandlers.clearTrackSelection.bind(
          this.eventHandlers,
        ),
      })
    }

    // Wait for style to be loaded before adding layers.
    // Use "idle" (fires after every render) instead of "load" (fires only once).
    // Also use isStyleLoaded() instead of loaded() — layers only need the style,
    // not all tiles, and loaded() can return false during re-renders triggered
    // by setPaintProperty, causing a hang if we wait for "load".
    if (this.map.isStyleLoaded()) {
      await addAllLayers()
    } else {
      await new Promise((resolve, reject) => {
        const onIdle = async () => {
          if (this.map.isStyleLoaded()) {
            this.map.off("idle", onIdle)
            try {
              await addAllLayers()
              resolve()
            } catch (e) {
              reject(e)
            }
          }
        }
        this.map.on("idle", onIdle)
      })
    }
  }

  /**
   * Try each GeoJSON source in order; fit map to the first one that has features.
   * @returns {boolean} true if bounds were fitted
   * @private
   */
  _fitToFirstAvailable(geojsonSources) {
    for (const geojson of geojsonSources) {
      if (geojson?.features?.length > 0) {
        this._fitMapToBounds(geojson)
        return true
      }
    }
    return false
  }

  /**
   * Fit map to data bounds. Handles Point, LineString, and Polygon geometries.
   * Sparse extreme outliers (stray GPS points, lone far-away arcs) are trimmed
   * first so one bad coordinate can't drag the viewport into the ocean.
   * @private
   */
  _fitMapToBounds(geojson, { animate = false, skipIfCovered = false } = {}) {
    if (!geojson?.features?.length) return

    const coords = []

    for (const feature of geojson.features) {
      const { type, coordinates } = feature.geometry
      if (type === "Point") {
        coords.push(coordinates)
      } else if (type === "LineString") {
        coords.push(...coordinates)
      } else if (type === "Polygon" || type === "MultiLineString") {
        for (const ring of coordinates) {
          coords.push(...ring)
        }
      }
    }

    const bounds = new maplibregl.LngLatBounds()
    for (const coord of trimOutlierCoords(coords)) {
      bounds.extend(coord)
    }

    if (bounds.isEmpty()) return
    if (skipIfCovered && this._boundsCovered(bounds)) return

    this.map.fitBounds(bounds, {
      padding: 50,
      maxZoom: 15,
      animate,
    })
  }

  /**
   * Whether the current viewport already contains the given bounds.
   * @private
   */
  _boundsCovered(bounds) {
    const view = this.map.getBounds()
    return (
      view.contains(bounds.getSouthWest()) &&
      view.contains(bounds.getNorthEast())
    )
  }

  /**
   * Show a persistent upgrade banner for Lite users when the queried date
   * range extends beyond the 12-month data window.
   * @private
   */
  _showDataWindowBanner() {
    const startDate = new Date(this.controller.startDateValue)
    const twelveMonthsAgo = new Date()
    twelveMonthsAgo.setMonth(twelveMonthsAgo.getMonth() - 12)

    if (startDate < twelveMonthsAgo) {
      UpgradeBanner.show({
        message: "Your Lite plan includes the last 12 months of data.",
        upgradeUrl: this.controller.upgradeUrlValue,
        utmContent: "data_retention",
      })
    }
  }
}
