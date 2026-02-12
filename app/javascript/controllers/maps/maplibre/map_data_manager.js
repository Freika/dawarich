import maplibregl from "maplibre-gl"
import { Toast } from "maps_maplibre/components/toast"
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

    performanceMonitor.mark("load-map-data")

    if (showLoading) {
      this.controller.showProgress()
    }

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

      // 2. Fetch data with incremental callbacks
      const data = await this.dataLoader.fetchMapData(startDate, endDate, {
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

      // 4. Store data for timeline and other features
      this.lastLoadedData = data

      // 5. Fit bounds if requested
      if (fitBounds && data.points.length > 0) {
        this._fitMapToBounds(data.pointsGeoJSON)
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

      // Safety net: if the counter didn't complete (e.g. no sources expected),
      // ensure the badge is dismissed after a short delay.
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

      const { points, pointsGeoJSON, routesGeoJSON, routesBaseGeoJSON } =
        await this.dataLoader.fetchPointsData(
          this.controller.startDateValue,
          this.controller.endDateValue,
        )

      if (!this.lastLoadedData) this.lastLoadedData = {}
      this.lastLoadedData.points = points
      this.lastLoadedData.pointsGeoJSON = pointsGeoJSON
      this.lastLoadedData.routesGeoJSON = routesGeoJSON
      this.lastLoadedData.routesBaseGeoJSON = routesBaseGeoJSON

      this._updateLayerBySource("points", pointsGeoJSON)
      this._updateLayerBySource("heatmap", pointsGeoJSON)
      this._updateLayerBySource("routes", routesGeoJSON)
      this._updateLayerBySource("routes-base", routesBaseGeoJSON)
      this._updateLayerBySource("fog", pointsGeoJSON)
      this._updateLayerBySource("scratch", pointsGeoJSON)

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
    }
    const layerName = layerMap[source]
    if (!layerName) return

    const layer = this.layerManager?.getLayer(layerName)
    if (layer) {
      layer.update(geoJSON)
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
        this.map.once("idle", async () => {
          try {
            await addAllLayers()
            resolve()
          } catch (e) {
            reject(e)
          }
        })
      })
    }
  }

  /**
   * Fit map to data bounds
   * @private
   */
  _fitMapToBounds(geojson) {
    if (!geojson?.features?.length) {
      return
    }

    const coordinates = geojson.features.map((f) => f.geometry.coordinates)

    const bounds = coordinates.reduce((bounds, coord) => {
      return bounds.extend(coord)
    }, new maplibregl.LngLatBounds(coordinates[0], coordinates[0]))

    this.map.fitBounds(bounds, {
      padding: 50,
      maxZoom: 15,
      animate: false,
    })
  }
}
