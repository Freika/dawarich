import maplibregl from "maplibre-gl"
import { Toast } from "maps_maplibre/components/toast"
import { performanceMonitor } from "maps_maplibre/utils/performance_monitor"

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
   * @param {string} startDate - Start date for data range
   * @param {string} endDate - End date for data range
   * @param {Object} options - Loading options
   */
  async loadMapData(startDate, endDate, options = {}) {
    const {
      showLoading = true,
      fitBounds = true,
      showToast = true,
      onProgress = null,
    } = options

    performanceMonitor.mark("load-map-data")

    if (showLoading) {
      this.controller.showProgress()
    }

    try {
      // Fetch data from API with background loading callbacks
      const data = await this.dataLoader.fetchMapData(
        startDate,
        endDate,
        showLoading ? onProgress : null,
        {
          // Callback when tracks finish loading in background
          onTracksLoaded: (tracksGeoJSON) => {
            console.log("[MapDataManager] Updating tracks layer from background load")
            this._updateTracksLayer(tracksGeoJSON)
          },
          // Callback when photos finish loading in background
          onPhotosLoaded: (photosGeoJSON) => {
            console.log("[MapDataManager] Updating photos layer from background load")
            this._updatePhotosLayer(photosGeoJSON)
          },
        }
      )

      // Store visits for filtering
      this.filterManager.setAllVisits(data.visits)

      // Store data for timeline and other features
      this.lastLoadedData = data

      // Setup layers (with empty tracks/photos initially)
      await this._setupLayers(data)

      // Fit bounds if requested
      if (fitBounds && data.points.length > 0) {
        this._fitMapToBounds(data.pointsGeoJSON)
      }

      // Show success message
      if (showToast) {
        const pointText = data.points.length === 1 ? "point" : "points"
        Toast.success(`Loaded ${data.points.length} location ${pointText}`)
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
      // Also update stored data
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
      // Also update stored data
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

    // Always use Promise-based approach for consistent timing
    await new Promise((resolve) => {
      if (this.map.loaded()) {
        addAllLayers().then(resolve)
      } else {
        this.map.once("load", async () => {
          await addAllLayers()
          resolve()
        })
      }
    })
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
