import { translate } from "i18n"
import * as maplibregl from "maplibre-gl"
import { Toast } from "maps_maplibre/components/toast"
import { UpgradeBanner } from "maps_maplibre/components/upgrade_banner"
import { flightWindows } from "maps_maplibre/utils/flight_mask"
import { trimOutlierCoords } from "maps_maplibre/utils/geometry"
import { isGatedPlan } from "maps_maplibre/utils/layer_gate"
import { overlayAwarePadding } from "maps_maplibre/utils/map_padding"
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
    this._pointsGeneration = 0
    this._pointsArrivalGeneration = 0
    this._pointsStale = false
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
    const loadGeneration = (this._loadGeneration || 0) + 1
    this._loadGeneration = loadGeneration
    this._hasFittedBounds = false
    this.lastLoadedData = null
    this._pointsLoadPromise = null
    const isCurrent = () => loadGeneration === this._loadGeneration
    const historyBoundsPromise =
      fitBounds && this.controller.api?.fetchHistoryBounds
        ? this.controller.api
            .fetchHistoryBounds({ start_at: startDate, end_at: endDate })
            .catch((error) => {
              console.warn("Failed to fetch history bounds:", error)
              return null
            })
        : Promise.resolve(null)

    performanceMonitor.mark("load-map-data")

    if (showLoading) {
      this.controller.showProgress()
    }

    // Hoisted out of `try` so the `finally` block can await background
    // work (tracks / photos) before deciding whether to dismiss the badge.
    let data = null

    try {
      this.layerManager.updatePointTileRange(startDate, endDate)

      // 1. Initialize all layers with empty data for correct z-ordering
      await this._setupLayers(
        {
          visitsGeoJSON: EMPTY_GEOJSON,
          photosGeoJSON: EMPTY_GEOJSON,
          areasGeoJSON: EMPTY_GEOJSON,
          placesGeoJSON: EMPTY_GEOJSON,
          flightsGeoJSON: EMPTY_GEOJSON,
        },
        isCurrent,
      )
      if (!isCurrent()) return null

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
          ? (info) => {
              if (isCurrent()) this.controller.updateLoadingCounts(info)
            }
          : null,
        onLayerData: (source, geoJSON) => {
          if (isCurrent()) this._updateLayerBySource(source, geoJSON)
        },
        onPhotosLoaded: (photosGeoJSON) => {
          if (!isCurrent()) return
          console.log(
            "[MapDataManager] Updating photos layer from background load",
          )
          this._updatePhotosLayer(photosGeoJSON)
        },
      })
      if (!isCurrent()) return null

      // 3. Store visits for filtering
      this.filterManager.setAllVisits(data.visits)

      // 4. Store data for replay and other features
      this.lastLoadedData = data
      this.applyFlightMask()

      // 5. Show upsell banner for Lite users when searching outside the 12-month window
      if (isGatedPlan(this.controller.userPlanValue)) {
        this._showDataWindowBanner()
      }

      // 6. Fit bounds if requested.
      if (fitBounds) {
        const historyBounds = await historyBoundsPromise
        if (isCurrent()) {
          this._hasFittedBounds = this._fitToHistoryBounds(historyBounds)
        }
        if (isCurrent() && !this._hasFittedBounds) {
          this._hasFittedBounds = this._fitToFirstAvailable([
            data.visitsGeoJSON,
            data.areasGeoJSON,
            data.placesGeoJSON,
          ])
        }
      }
      if (!isCurrent()) return null

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
      if (!isCurrent()) return null
      console.error("[MapDataManager] Failed to load map data:", error)
      if (showLoading) {
        this.controller.hideProgress()
      }
      Toast.error(
        translate("messages.failed_to_load_location_data_please_try_again"),
      )
      throw error
    } finally {
      const duration = performanceMonitor.measure("load-map-data")
      console.log(`[Performance] Map data loaded in ${duration}ms`)

      // Wait for background fetches (tracks, photos) to finish before
      // running the safety net. If we don't, the badge gets force-hidden
      // while tracks are still loading — see issue: "loader disappears
      // before tracks are rendered."
      if (isCurrent() && data?.backgroundReady) {
        try {
          await data.backgroundReady
        } catch {
          /* allSettled never rejects but be defensive */
        }
      }

      // Safety net: if the counter didn't complete (e.g. no sources expected,
      // or the user has every layer disabled), ensure the badge is dismissed
      // after a short delay so it doesn't linger forever.
      if (
        isCurrent() &&
        showLoading &&
        this.controller.hasProgressBadgeTarget
      ) {
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
    let generation
    do {
      if (!this._pointsStale && this.lastLoadedData?.points?.length > 0) return
      generation = this._pointsGeneration
      if (!this._pointsLoadPromise) {
        const promise = this._loadPoints()
        this._pointsLoadPromise = promise
        const clearPending = () => {
          if (this._pointsLoadPromise === promise)
            this._pointsLoadPromise = null
        }
        void promise.then(clearPending, clearPending)
      }
      await this._pointsLoadPromise
    } while (generation !== this._pointsGeneration)
  }

  invalidatePoints({ appendOnly = false } = {}) {
    this._pointsStale = true
    if (appendOnly) {
      this._pointsArrivalGeneration += 1
      return
    }
    this._pointsGeneration += 1
    this._pointsLoadPromise = null
    if (!this.lastLoadedData) return
    this.lastLoadedData.points = []
    this.lastLoadedData.pointsGeoJSON = EMPTY_GEOJSON
  }

  /** Fetch exact points only for explicit bounded consumers such as replay. */
  async _loadPoints() {
    const loadGeneration = this._loadGeneration
    const pointsGeneration = this._pointsGeneration
    const isCurrent = () =>
      loadGeneration === this._loadGeneration &&
      pointsGeneration === this._pointsGeneration
    try {
      this.controller.showProgress()
      this.controller.updateLoadingCounts({
        counts: { points: 0 },
        isComplete: false,
      })

      for (let attempt = 0; attempt < 2; attempt += 1) {
        const arrivalGeneration = this._pointsArrivalGeneration
        const { points, pointsGeoJSON } = await this.dataLoader.fetchPointsData(
          this.controller.startDateValue,
          this.controller.endDateValue,
        )
        if (!isCurrent()) return

        const stale = arrivalGeneration !== this._pointsArrivalGeneration
        if (stale && attempt === 0) continue

        if (!this.lastLoadedData) this.lastLoadedData = {}
        this.lastLoadedData.points = points
        this.lastLoadedData.pointsGeoJSON = pointsGeoJSON
        this._pointsStale = stale

        this.controller.updateLoadingCounts({
          counts: { points: points.length },
          isComplete: true,
        })
        return
      }
    } finally {
      if (
        loadGeneration === this._loadGeneration &&
        (pointsGeneration === this._pointsGeneration ||
          !this._pointsLoadPromise)
      )
        this.controller.hideProgress()
    }
  }

  /**
   * Update a specific layer by source name
   * @private
   */
  _updateLayerBySource(source, geoJSON) {
    const layerMap = {
      visits: "visits",
      areas: "areas",
      places: "places",
      photos: "photos",
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
   * Give AirTrail flights render priority using filters on both MVT layers.
   */
  applyFlightMask() {
    const flightsLayer = this.layerManager?.getLayer("flights")
    const data = this.lastLoadedData
    if (!data) return

    const windows = flightsLayer?.visible
      ? flightWindows(data.flightsGeoJSON)
      : []
    this.layerManager?.getLayer("points-mvt")?.setFlightWindows(windows)
    this.layerManager?.getLayer("tracks-mvt")?.setFlightWindows(windows)
    this.layerManager?.getLayer("map-editor")?.reapplyTileFilters()
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
  async _setupLayers(data, isCurrent = () => true) {
    const addAllLayers = async () => {
      if (!isCurrent()) return
      await this.layerManager.addAllLayers(
        data.visitsGeoJSON,
        data.photosGeoJSON,
        data.areasGeoJSON,
        data.placesGeoJSON,
        data.flightsGeoJSON,
        isCurrent,
      )
      if (!isCurrent()) return

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
        handleTrackClick: this.eventHandlers.handleTrackClick.bind(
          this.eventHandlers,
        ),
        clearTrackSelection: this.eventHandlers.clearTrackSelection.bind(
          this.eventHandlers,
        ),
        clearPointSelection: this.eventHandlers.clearPointSelection.bind(
          this.eventHandlers,
        ),
        canDragPoint: (properties) =>
          this.eventHandlers.pointDrag?.canDrag(properties) === true,
      })
    }

    // Wait for style to be loaded before adding layers.
    // Check on "render" as well as "idle": an animated layer keeps the map
    // rendering, and "idle" never fires while it runs.
    // Also use isStyleLoaded() instead of loaded() — layers only need the style,
    // not all tiles, and loaded() can return false during re-renders triggered
    // by setPaintProperty, causing a hang if we wait for "load".
    if (this.map.isStyleLoaded()) {
      await addAllLayers()
    } else {
      await new Promise((resolve, reject) => {
        const onReady = async () => {
          if (this.map.isStyleLoaded()) {
            this.map.off("idle", onReady)
            this.map.off("render", onReady)
            if (!isCurrent()) {
              resolve()
              return
            }
            try {
              await addAllLayers()
              resolve()
            } catch (e) {
              reject(e)
            }
          }
        }
        this.map.on("idle", onReady)
        this.map.on("render", onReady)
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
        return this._fitMapToBounds(geojson)
      }
    }
    return false
  }

  _fitToHistoryBounds(bounds) {
    const values = bounds
      ? [bounds.min_lng, bounds.min_lat, bounds.max_lng, bounds.max_lat].map(
          Number,
        )
      : []
    if (values.length !== 4 || values.some((value) => !Number.isFinite(value)))
      return false

    const [minLng, minLat, maxLng, maxLat] = values
    return this._fitMapToBounds({
      type: "FeatureCollection",
      features: [
        {
          type: "Feature",
          geometry: { type: "Point", coordinates: [minLng, minLat] },
          properties: {},
        },
        {
          type: "Feature",
          geometry: { type: "Point", coordinates: [maxLng, maxLat] },
          properties: {},
        },
      ],
    })
  }

  /**
   * Fit map to data bounds. Handles Point, LineString, and Polygon geometries.
   * Sparse extreme outliers (stray GPS points, lone far-away arcs) are trimmed
   * first so one bad coordinate can't drag the viewport into the ocean.
   * @private
   */
  _fitMapToBounds(geojson, { animate = false, skipIfCovered = false } = {}) {
    if (!geojson?.features?.length) return false

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

    if (bounds.isEmpty()) return false
    if (skipIfCovered && this._boundsCovered(bounds)) return false

    const mapRect = this.map.getContainer()?.getBoundingClientRect()
    const toolbarRect = document
      .querySelector(".map-button-cluster")
      ?.getBoundingClientRect()

    this.map.fitBounds(bounds, {
      padding: overlayAwarePadding(mapRect, toolbarRect),
      maxZoom: 15,
      animate,
    })
    return true
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
        message: translate(
          "messages.your_lite_plan_includes_the_last_12_months_of_data",
        ),
        upgradeUrl: this.controller.upgradeUrlValue,
        utmContent: "data_retention",
      })
    }
  }
}
