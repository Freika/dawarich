import { AreasLayer } from "maps_maplibre/layers/areas_layer"
import { FamilyLayer } from "maps_maplibre/layers/family_layer"
import { FogLayer } from "maps_maplibre/layers/fog_layer"
import { HeatmapLayer } from "maps_maplibre/layers/heatmap_layer"
import { PhotosLayer } from "maps_maplibre/layers/photos_layer"
import { PlacesLayer } from "maps_maplibre/layers/places_layer"
import { PointsLayer } from "maps_maplibre/layers/points_layer"
import { RecentPointLayer } from "maps_maplibre/layers/recent_point_layer"
import { ReplayMarkerLayer } from "maps_maplibre/layers/replay_marker_layer"
import { RoutesLayer } from "maps_maplibre/layers/routes_layer"
import { TracksLayer } from "maps_maplibre/layers/tracks_layer"
import { VisitsLayer } from "maps_maplibre/layers/visits_layer"
import { lazyLoader } from "maps_maplibre/utils/lazy_loader"
import { performanceMonitor } from "maps_maplibre/utils/performance_monitor"

/**
 * Manages all map layers lifecycle and visibility
 */
export class LayerManager {
  constructor(map, settings, api) {
    this.map = map
    this.settings = settings
    this.api = api
    this.layers = {}
    this.eventHandlersSetup = false
  }

  /**
   * Add or update all layers with provided data
   */
  async addAllLayers(
    pointsGeoJSON,
    routesGeoJSON,
    visitsGeoJSON,
    photosGeoJSON,
    areasGeoJSON,
    tracksGeoJSON,
    placesGeoJSON,
  ) {
    performanceMonitor.mark("add-layers")

    // Layer order matters - layers added first render below layers added later
    // Order: scratch (bottom) -> heatmap -> areas -> tracks -> routes (visual) -> visits -> places -> photos -> family -> points -> routes-hit (interaction) -> recent-point (top) -> fog (canvas overlay)
    // Note: routes-hit is above points visually but points dragging takes precedence via event ordering

    await this._addScratchLayer(pointsGeoJSON)
    this._addHeatmapLayer(pointsGeoJSON)
    this._addAreasLayer(areasGeoJSON)
    this._addTracksLayer(tracksGeoJSON)
    this._addRoutesLayer(routesGeoJSON)
    this._addVisitsLayer(visitsGeoJSON)
    this._addPlacesLayer(placesGeoJSON)

    // Add photos layer with error handling (async, might fail loading images)
    try {
      await this._addPhotosLayer(photosGeoJSON)
    } catch (error) {
      console.warn("Failed to add photos layer:", error)
    }

    this._addFamilyLayer()
    this._addPointsLayer(pointsGeoJSON)
    this._addRoutesHitLayer() // Add hit target layer after points, will be on top visually
    this._addRecentPointLayer()
    this._addReplayMarkerLayer()
    this._addFogLayer(pointsGeoJSON)

    performanceMonitor.measure("add-layers")
  }

  /**
   * Setup event handlers for layer interactions
   * Only sets up handlers once to prevent duplicates
   */
  setupLayerEventHandlers(handlers) {
    if (this.eventHandlersSetup) {
      return
    }

    // Click handlers
    this.map.on("click", "points", handlers.handlePointClick)
    this.map.on("click", "visits", handlers.handleVisitClick)
    this.map.on("click", "photos", handlers.handlePhotoClick)
    this.map.on("click", "places", handlers.handlePlaceClick)
    // Areas have multiple layers (fill, outline, labels)
    this.map.on("click", "areas-fill", handlers.handleAreaClick)
    this.map.on("click", "areas-outline", handlers.handleAreaClick)
    this.map.on("click", "areas-labels", handlers.handleAreaClick)

    // Track click handler (debug mode for segment visualization)
    this.map.on("click", "tracks", handlers.handleTrackClick)

    // Route handlers - use routes-hit layer for better interactivity
    this.map.on("click", "routes-hit", handlers.handleRouteClick)
    this.map.on("mouseenter", "routes-hit", handlers.handleRouteHover)
    this.map.on("mouseleave", "routes-hit", handlers.handleRouteMouseLeave)

    // Cursor change on hover
    this.map.on("mouseenter", "points", () => {
      this.map.getCanvas().style.cursor = "pointer"
    })
    this.map.on("mouseleave", "points", () => {
      this.map.getCanvas().style.cursor = ""
    })
    this.map.on("mouseenter", "visits", () => {
      this.map.getCanvas().style.cursor = "pointer"
    })
    this.map.on("mouseleave", "visits", () => {
      this.map.getCanvas().style.cursor = ""
    })
    this.map.on("mouseenter", "photos", () => {
      this.map.getCanvas().style.cursor = "pointer"
    })
    this.map.on("mouseleave", "photos", () => {
      this.map.getCanvas().style.cursor = ""
    })
    this.map.on("mouseenter", "places", () => {
      this.map.getCanvas().style.cursor = "pointer"
    })
    this.map.on("mouseleave", "places", () => {
      this.map.getCanvas().style.cursor = ""
    })
    // Track cursor handlers
    this.map.on("mouseenter", "tracks", () => {
      this.map.getCanvas().style.cursor = "pointer"
    })
    this.map.on("mouseleave", "tracks", () => {
      this.map.getCanvas().style.cursor = ""
    })
    // Route cursor handlers - use routes-hit layer
    this.map.on("mouseenter", "routes-hit", () => {
      this.map.getCanvas().style.cursor = "pointer"
    })
    this.map.on("mouseleave", "routes-hit", () => {
      this.map.getCanvas().style.cursor = ""
    })
    // Areas hover handlers for all sub-layers
    const areaLayers = ["areas-fill", "areas-outline", "areas-labels"]
    areaLayers.forEach((layerId) => {
      // Only add handlers if layer exists
      if (this.map.getLayer(layerId)) {
        this.map.on("mouseenter", layerId, () => {
          this.map.getCanvas().style.cursor = "pointer"
        })
        this.map.on("mouseleave", layerId, () => {
          this.map.getCanvas().style.cursor = ""
        })
      }
    })

    // Map-level click to deselect routes and tracks
    this.map.on("click", (e) => {
      const routeFeatures = this.map.queryRenderedFeatures(e.point, {
        layers: ["routes-hit"],
      })
      const trackFeatures = this.map.queryRenderedFeatures(e.point, {
        layers: ["tracks"],
      })
      // Track points are part of a selected track — clicking them should not clear the selection
      const trackPointFeatures = this.map.getLayer("track-points")
        ? this.map.queryRenderedFeatures(e.point, { layers: ["track-points"] })
        : []
      if (routeFeatures.length === 0) {
        handlers.clearRouteSelection()
      }
      if (trackFeatures.length === 0 && trackPointFeatures.length === 0) {
        handlers.clearTrackSelection()
      }
    })

    this.eventHandlersSetup = true
  }

  /**
   * Toggle layer visibility
   */
  toggleLayer(layerName) {
    const layer = this.layers[`${layerName}Layer`]
    if (!layer) return null

    layer.toggle()
    return layer.visible
  }

  /**
   * Get layer instance
   */
  getLayer(layerName) {
    return this.layers[`${layerName}Layer`]
  }

  /**
   * Register a dynamically created layer
   * @param {string} layerName - Layer name (without 'Layer' suffix)
   * @param {object} layerInstance - Layer instance
   */
  registerLayer(layerName, layerInstance) {
    this.layers[`${layerName}Layer`] = layerInstance
  }

  /**
   * Clear all layer references (for style changes)
   */
  clearLayerReferences() {
    // Stop animations on layers that have them before orphaning
    if (this.layers.tracksLayer?._stopFlowAnimation) {
      this.layers.tracksLayer._stopFlowAnimation()
    }
    this.layers = {}
    this.eventHandlersSetup = false
  }

  // Private methods for individual layer management

  async _addScratchLayer(pointsGeoJSON) {
    try {
      if (!this.layers.scratchLayer && this.settings.scratchEnabled) {
        const ScratchLayer = await lazyLoader.loadLayer("scratch")
        this.layers.scratchLayer = new ScratchLayer(this.map, {
          visible: true,
          apiClient: this.api,
        })
        await this.layers.scratchLayer.add(pointsGeoJSON)
      } else if (this.layers.scratchLayer) {
        await this.layers.scratchLayer.update(pointsGeoJSON)
      }
    } catch (error) {
      console.warn("Failed to load scratch layer:", error)
    }
  }

  _addHeatmapLayer(pointsGeoJSON) {
    if (!this.layers.heatmapLayer) {
      this.layers.heatmapLayer = new HeatmapLayer(this.map, {
        visible: this.settings.heatmapEnabled,
      })
      this.layers.heatmapLayer.add(pointsGeoJSON)
    } else {
      this.layers.heatmapLayer.update(pointsGeoJSON)
    }
  }

  _addAreasLayer(areasGeoJSON) {
    if (!this.layers.areasLayer) {
      this.layers.areasLayer = new AreasLayer(this.map, {
        visible: this.settings.areasEnabled || false,
      })
      this.layers.areasLayer.add(areasGeoJSON)
    } else {
      this.layers.areasLayer.update(areasGeoJSON)
    }
  }

  _addTracksLayer(tracksGeoJSON) {
    if (!this.layers.tracksLayer) {
      this.layers.tracksLayer = new TracksLayer(this.map, {
        visible: this.settings.tracksEnabled || false,
      })
      this.layers.tracksLayer.add(tracksGeoJSON)
    } else {
      this.layers.tracksLayer.update(tracksGeoJSON)
    }
  }

  _addRoutesLayer(routesGeoJSON) {
    if (!this.layers.routesLayer) {
      this.layers.routesLayer = new RoutesLayer(this.map, {
        visible: this.settings.routesVisible !== false, // Default true unless explicitly false
      })
      this.layers.routesLayer.add(routesGeoJSON)
    } else {
      this.layers.routesLayer.update(routesGeoJSON)
    }
  }

  _addRoutesHitLayer() {
    // Add invisible hit target layer for routes
    // Use beforeId to place it BELOW points layer so points remain draggable on top
    if (
      !this.map.getLayer("routes-hit") &&
      this.map.getSource("routes-source")
    ) {
      this.map.addLayer(
        {
          id: "routes-hit",
          type: "line",
          source: "routes-source",
          minzoom: 8, // Match main routes layer visibility
          layout: {
            "line-join": "round",
            "line-cap": "round",
          },
          paint: {
            "line-color": "transparent",
            "line-width": 20, // Much wider for easier clicking/hovering
            "line-opacity": 0,
          },
        },
        "points",
      ) // Add before 'points' layer so points are on top for interaction
      // Match visibility with routes layer
      const routesLayer = this.layers.routesLayer
      if (routesLayer && !routesLayer.visible) {
        this.map.setLayoutProperty("routes-hit", "visibility", "none")
      }
    }
  }

  _addVisitsLayer(visitsGeoJSON) {
    if (!this.layers.visitsLayer) {
      this.layers.visitsLayer = new VisitsLayer(this.map, {
        visible: this.settings.visitsEnabled || false,
      })
      this.layers.visitsLayer.add(visitsGeoJSON)
    } else {
      this.layers.visitsLayer.update(visitsGeoJSON)
    }
  }

  _addPlacesLayer(placesGeoJSON) {
    if (!this.layers.placesLayer) {
      this.layers.placesLayer = new PlacesLayer(this.map, {
        visible: this.settings.placesEnabled || false,
      })
      this.layers.placesLayer.add(placesGeoJSON)
    } else {
      this.layers.placesLayer.update(placesGeoJSON)
    }
  }

  async _addPhotosLayer(photosGeoJSON) {
    console.log(
      "[Photos] Adding photos layer, visible:",
      this.settings.photosEnabled,
    )
    if (!this.layers.photosLayer) {
      this.layers.photosLayer = new PhotosLayer(this.map, {
        visible: this.settings.photosEnabled || false,
      })
      console.log("[Photos] Created new PhotosLayer instance")
      await this.layers.photosLayer.add(photosGeoJSON)
      console.log("[Photos] Added photos to layer")
    } else {
      console.log("[Photos] Updating existing PhotosLayer")
      await this.layers.photosLayer.update(photosGeoJSON)
      console.log("[Photos] Updated photos layer")
    }
  }

  _addFamilyLayer() {
    if (!this.layers.familyLayer) {
      this.layers.familyLayer = new FamilyLayer(this.map, {
        visible: this.settings.familyEnabled || false,
      })
      this.layers.familyLayer.add({ type: "FeatureCollection", features: [] })
    }
  }

  _addPointsLayer(pointsGeoJSON) {
    if (!this.layers.pointsLayer) {
      this.layers.pointsLayer = new PointsLayer(this.map, {
        visible: this.settings.pointsVisible !== false, // Default true unless explicitly false
        apiClient: this.api,
        layerManager: this,
      })
      this.layers.pointsLayer.add(pointsGeoJSON)
    } else {
      this.layers.pointsLayer.update(pointsGeoJSON)
    }
  }

  _addRecentPointLayer() {
    if (!this.layers.recentPointLayer) {
      this.layers.recentPointLayer = new RecentPointLayer(this.map, {
        visible: false, // Initially hidden, shown only when live mode is enabled
      })
      this.layers.recentPointLayer.add({
        type: "FeatureCollection",
        features: [],
      })
    }
  }

  _addReplayMarkerLayer() {
    if (!this.layers.replayMarkerLayer) {
      this.layers.replayMarkerLayer = new ReplayMarkerLayer(this.map, {
        visible: false, // Initially hidden, shown when replay is active
      })
      this.layers.replayMarkerLayer.add({
        type: "FeatureCollection",
        features: [],
      })
    }
  }

  _addFogLayer(pointsGeoJSON) {
    // Always create fog layer for backward compatibility
    if (!this.layers.fogLayer) {
      this.layers.fogLayer = new FogLayer(this.map, {
        clearRadius: this.settings.fogOfWarRadius || 1000,
        visible: this.settings.fogEnabled || false,
      })
      this.layers.fogLayer.add(pointsGeoJSON)
    } else {
      this.layers.fogLayer.update(pointsGeoJSON)
    }
  }
}
