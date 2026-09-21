import { shouldShowPointPopup } from "controllers/maps/maplibre/event_handlers"
import { translate } from "i18n"
import { Toast } from "maps_maplibre/components/toast"
import { AnomaliesLayer } from "maps_maplibre/layers/anomalies_layer"
import { FamilyLayer } from "maps_maplibre/layers/family_layer"
import { FlightsLayer } from "maps_maplibre/layers/flights_layer"
import { FogLayer } from "maps_maplibre/layers/fog_layer"
import { HexagonLayer } from "maps_maplibre/layers/hexagon_layer"
import { PhotosLayer } from "maps_maplibre/layers/photos_layer"
import { PlacesLayer } from "maps_maplibre/layers/places_layer"
import { PointsMvtLayer } from "maps_maplibre/layers/points_mvt_layer"
import { RecentPointLayer } from "maps_maplibre/layers/recent_point_layer"
import { ReplayMarkerLayer } from "maps_maplibre/layers/replay_marker_layer"
import { TracksLayer } from "maps_maplibre/layers/tracks_layer"
import { TracksMvtLayer } from "maps_maplibre/layers/tracks_mvt_layer"
import { VisitsLayer } from "maps_maplibre/layers/visits_layer"
import { lazyLoader } from "maps_maplibre/utils/lazy_loader"
import { performanceMonitor } from "maps_maplibre/utils/performance_monitor"
import { SettingsManager } from "maps_maplibre/utils/settings_manager"

const EMPTY_GEOJSON = { type: "FeatureCollection", features: [] }

/**
 * Manages all map layers lifecycle and visibility
 */
export class LayerManager {
  constructor(map, settings, api, controller) {
    this.map = map
    this.settings = settings
    this.api = api
    this.controller = controller
    this.apiKey = controller?.apiKeyValue || null
    this.layers = {}
    this.eventHandlersSetup = false
    this.eventHandlerCleanups = []
    this.pointTileRange = { startAt: null, endAt: null }
    this._styleGeneration = 0
  }

  /**
   * Add or update all layers with provided data
   */
  async addAllLayers(
    visitsGeoJSON,
    photosGeoJSON,
    placesGeoJSON,
    flightsGeoJSON,
    isCurrent = () => true,
  ) {
    performanceMonitor.mark("add-layers")

    // Layer order matters: visited countries at the bottom, MVT journey data
    // above contextual overlays, and transient/replay markers at the top.

    this._addHexagonLayer()
    this._addTracksLayer(EMPTY_GEOJSON)
    this._addFlightsLayer(flightsGeoJSON)
    this._addVisitsLayer(visitsGeoJSON)
    this._addPlacesLayer(placesGeoJSON)

    // Add photos layer with error handling (async, might fail loading images)
    try {
      await this._addPhotosLayer(photosGeoJSON)
    } catch (error) {
      console.warn("Failed to add photos layer:", error)
    }
    if (!isCurrent()) return

    this._addFamilyLayer()
    this._addTracksMvtLayer()
    this._addAnomaliesLayer()
    this._addPointsMvtLayer()
    this._addRecentPointLayer()
    this._addReplayMarkerLayer()
    this._addFogLayer(EMPTY_GEOJSON)
    // Membership may scan a large history. The blank-filter Scratch source
    // attaches below the overlays when ready, without holding up tile layers.
    void this._addScratchLayer()

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

    const subscribe = (...args) => {
      const subscription = this.map.on(...args)
      this.eventHandlerCleanups.push(() => {
        if (subscription?.unsubscribe) subscription.unsubscribe()
        else this.map.off(...args)
      })
    }

    // Click handlers
    subscribe("click", "points-mvt", handlers.handlePointClick)
    subscribe("click", "visits", handlers.handleVisitClick)
    subscribe("click", "photos", handlers.handlePhotoClick)
    subscribe("click", "places", handlers.handlePlaceClick)
    subscribe("click", "places-radius-fill", handlers.handlePlaceClick)
    subscribe("click", "places-radius-outline", handlers.handlePlaceClick)
    subscribe("click", "places-labels", handlers.handlePlaceClick)

    // Anomalies click handler
    subscribe("click", "anomalies", handlers.handleAnomalyClick)

    // MVT track fragments carry the same id property; the click flow fetches
    // the full geometry by id, so a clipped fragment is a valid entry point.
    subscribe("click", "tracks-mvt", handlers.handleTrackClick)
    subscribe("mouseenter", "tracks-mvt", () => {
      this.map.getCanvas().style.cursor = "pointer"
    })
    subscribe("mouseleave", "tracks-mvt", () => {
      this.map.getCanvas().style.cursor = ""
    })

    // Cursor change on hover
    // Merged cells carry no point to open, so they must not promise a click.
    // mousemove, not mouseenter: clickable and merged features sit side by side
    // in this layer, and mouseenter fires only on entering the layer as a whole.
    subscribe("mousemove", "points-mvt", (e) => {
      const properties = e.features?.[0]?.properties
      let cursor = ""
      if (shouldShowPointPopup(properties))
        cursor = handlers.canDragPoint?.(properties) ? "grab" : "pointer"
      this.map.getCanvas().style.cursor = cursor
    })
    subscribe("mouseleave", "points-mvt", () => {
      this.map.getCanvas().style.cursor = ""
    })
    subscribe("mouseenter", "visits", () => {
      this.map.getCanvas().style.cursor = "pointer"
    })
    subscribe("mouseleave", "visits", () => {
      this.map.getCanvas().style.cursor = ""
    })
    subscribe("mouseenter", "photos", () => {
      this.map.getCanvas().style.cursor = "pointer"
    })
    subscribe("mouseleave", "photos", () => {
      this.map.getCanvas().style.cursor = ""
    })
    const placeLayers = [
      "places",
      "places-radius-fill",
      "places-radius-outline",
      "places-labels",
    ]
    placeLayers.forEach((layerId) => {
      subscribe("mouseenter", layerId, () => {
        this.map.getCanvas().style.cursor = "pointer"
      })
      subscribe("mouseleave", layerId, () => {
        this.map.getCanvas().style.cursor = ""
      })
    })
    // Anomalies cursor handlers
    subscribe("mouseenter", "anomalies", () => {
      this.map.getCanvas().style.cursor = "pointer"
    })
    subscribe("mouseleave", "anomalies", () => {
      this.map.getCanvas().style.cursor = ""
    })
    // Map-level click clears the focused track selection.
    subscribe("click", (e) => {
      // Track points are part of a selected track — clicking them should not clear the selection
      const trackPointFeatures = this.map.getLayer("track-points")
        ? this.map.queryRenderedFeatures(e.point, { layers: ["track-points"] })
        : []
      // Tiled tracks select via their own click handler — without them here a
      // tiled-track click would deselect first and stay deselected whenever
      // the async detail fetch fails.
      const tiledTrackFeatures = this.map.getLayer("tracks-mvt")
        ? this.map.queryRenderedFeatures(e.point, { layers: ["tracks-mvt"] })
        : []
      if (tiledTrackFeatures.length === 0 && trackPointFeatures.length === 0) {
        handlers.clearTrackSelection()
        const tilePointFeatures = this.map.getLayer("points-mvt")
          ? this.map.queryRenderedFeatures(e.point, { layers: ["points-mvt"] })
          : []
        if (tilePointFeatures.length === 0) handlers.clearPointSelection()
      }
    })

    this.eventHandlersSetup = true
  }

  /**
   * Toggle layer visibility
   */
  toggleLayer(layerName) {
    const layer = this.getLayer(layerName)
    if (!layer) return null

    layer.toggle()
    return layer.visible
  }

  /**
   * Get layer instance
   */
  getLayer(layerName) {
    return (
      this.layers[`${layerName}Layer`] ||
      this.layers[`${this._normalizeLayerName(layerName)}Layer`]
    )
  }

  /**
   * Register a dynamically created layer
   * @param {string} layerName - Layer name (without 'Layer' suffix)
   * @param {object} layerInstance - Layer instance
   */
  registerLayer(layerName, layerInstance) {
    this.layers[`${this._normalizeLayerName(layerName)}Layer`] = layerInstance
  }

  updatePointTileRange(startAt, endAt) {
    this.pointTileRange = { startAt, endAt }

    for (const layerName of ["points-mvt", "tracks-mvt"]) {
      const layer = this.getLayer(layerName)
      if (layer) layer.update(this.pointTileRange)
    }
  }

  /**
   * Clear all layer references (for style changes)
   */
  clearLayerReferences() {
    this._styleGeneration += 1
    // Stop animations on layers that have them before orphaning
    if (this.layers.tracksLayer?._stopFlowAnimation) {
      this.layers.tracksLayer._stopFlowAnimation()
    }
    // Drag handlers live on the map, not the style, so an orphaned points
    // layer keeps moving points. setEditMode, not disableDragging: add() arms
    // enableDragging on a timer that re-checks editModeEnabled.
    this.controller?.eventHandlers?.teardownLayerInteractions()
    this.layers.mapEditorLayer?.dispose()
    // setStyle replaces style sources/layers, but every layer object may also
    // own map/document/DOM listeners, popups, markers or timers. Release every
    // instance while the old style still exists instead of special-casing the
    // leaks we happen to know about today.
    const uniqueLayers = new Set(Object.values(this.layers))
    for (const layer of uniqueLayers) {
      if (!layer || layer === this.layers.mapEditorLayer) continue
      if (typeof layer.remove === "function") layer.remove()
      else if (typeof layer._unwatchTileErrors === "function") {
        layer._unwatchTileErrors()
      }
    }
    for (const cleanup of this.eventHandlerCleanups || []) cleanup()
    this.eventHandlerCleanups = []
    this.layers = {}
    this.eventHandlersSetup = false
  }

  _normalizeLayerName(layerName) {
    return layerName.replace(/-([a-z])/g, (_match, letter) =>
      letter.toUpperCase(),
    )
  }

  // Private methods for individual layer management

  async _addScratchLayer() {
    const styleGeneration = this._styleGeneration
    try {
      if (!this.layers.scratchLayer && this.settings.scratchEnabled) {
        const ScratchLayer = await lazyLoader.loadLayer("scratch")
        if (styleGeneration !== this._styleGeneration) return
        if (this.layers.scratchLayer) return this.layers.scratchLayer.update()
        this.layers.scratchLayer = new ScratchLayer(this.map, {
          visible: true,
          apiClient: this.api,
          historyScope: () => ({
            startAt: this.pointTileRange.startAt,
            endAt: this.pointTileRange.endAt,
          }),
          onTileError: () =>
            Toast.retry(
              translate("messages.failed_to_load_visited_countries"),
              translate("messages.retry"),
              () => this.layers.scratchLayer?.refresh(),
            ),
          onMembershipError: () =>
            Toast.retry(
              translate("messages.failed_to_load_visited_countries"),
              translate("messages.retry"),
              () => this.layers.scratchLayer?.retryMembership(),
            ),
        })
        const beforeId = this.map.getLayer("hexagons-fill")
          ? "hexagons-fill"
          : null
        await this.layers.scratchLayer.add(undefined, beforeId)
      } else if (this.layers.scratchLayer) {
        await this.layers.scratchLayer.update()
      }
    } catch (error) {
      console.warn("Failed to load scratch layer:", error)
      if (!this.map.getLayer("scratch")) {
        this.layers.scratchLayer?.remove()
        this.layers.scratchLayer = null
      }
      Toast.retry(
        translate("messages.failed_to_load_visited_countries"),
        translate("messages.retry"),
        () => this._addScratchLayer(),
      )
    }
  }

  _addHexagonLayer() {
    if (this.layers.hexagonsLayer) return this.layers.hexagonsLayer
    this.layers.hexagonsLayer = new HexagonLayer(this.map, {
      visible: this.settings.hexagonsEnabled || false,
      api: this.api,
      controller: this.controller,
    })
    this.layers.hexagonsLayer.add({ type: "FeatureCollection", features: [] })
    return this.layers.hexagonsLayer
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

  _addFlightsLayer(flightsGeoJSON) {
    if (!this.layers.flightsLayer) {
      this.layers.flightsLayer = new FlightsLayer(this.map, {
        visible: this.settings.flightsEnabled || false,
        style: this.settings.mapStyle || "light",
      })
      this.layers.flightsLayer.add(flightsGeoJSON)
    } else {
      this.layers.flightsLayer.update(flightsGeoJSON)
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
        boundariesVisible: this.settings.placeBoundariesEnabled || false,
      })
      this.layers.placesLayer.add(placesGeoJSON)
    } else {
      this.layers.placesLayer.update(placesGeoJSON)
    }
  }

  async _addPhotosLayer(photosGeoJSON) {
    if (!this.layers.photosLayer) {
      this.layers.photosLayer = new PhotosLayer(this.map, {
        visible: this.settings.photosEnabled || false,
        timezone: this.settings.timezone,
      })
      await this.layers.photosLayer.add(photosGeoJSON)
    } else {
      await this.layers.photosLayer.update(photosGeoJSON)
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

  _addAnomaliesLayer() {
    if (!this.layers.anomaliesLayer) {
      this.layers.anomaliesLayer = new AnomaliesLayer(this.map, {
        visible: false,
        apiClient: this.api,
        timezone: this.settings.timezone,
      })
      this.layers.anomaliesLayer.add({
        type: "FeatureCollection",
        features: [],
      })
    }
  }

  // Tile-backed canonical Tracks layer; added below points so circles stay on
  // top of track lines.
  _addTracksMvtLayer() {
    if (!this.layers.tracksMvtLayer) {
      this.layers.tracksMvtLayer = new TracksMvtLayer(this.map, {
        tracksEnabled: this.settings.tracksEnabled === true,
        trackColor: SettingsManager.getSetting("trackColor"),
        apiKey: this.apiKey,
        importId: this.controller?.importIdValue || null,
        onTileError: () =>
          Toast.retry(
            translate("messages.failed_to_load_map_tiles"),
            translate("messages.retry"),
            () => {
              this.layers.tracksMvtLayer?.refresh()
              this.layers.mapEditorLayer?.reapplyTileFilters()
            },
          ),
        onEmptyTracks: () => Toast.info(translate("messages.tracks_pending")),
        ...this.pointTileRange,
      })
      this.layers.tracksMvtLayer.add(this.pointTileRange)
    } else {
      this.layers.tracksMvtLayer.update(this.pointTileRange)
    }
  }

  _addPointsMvtLayer() {
    if (!this.layers.pointsMvtLayer) {
      this.layers.pointsMvtLayer = new PointsMvtLayer(this.map, {
        heatmapVisible: Boolean(this.settings.heatmapEnabled),
        visible: this.settings.pointsVisible !== false,
        apiKey: this.apiKey,
        importId: this.controller?.importIdValue || null,
        styleName: this.settings.mapStyle,
        onTileError: () =>
          Toast.retry(
            translate("messages.failed_to_load_map_tiles"),
            translate("messages.retry"),
            () => {
              this.layers.pointsMvtLayer?.refresh()
              this.layers.mapEditorLayer?.reapplyTileFilters()
            },
          ),
        ...this.pointTileRange,
      })
      this.layers.pointsMvtLayer.add(this.pointTileRange)
    } else {
      this.layers.pointsMvtLayer.update(this.pointTileRange)
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
    const tiledFog = (this.settings.fogOfWarMode || "points") !== "hexagons"
    // Always create fog layer for backward compatibility
    if (!this.layers.fogLayer) {
      this.layers.fogLayer = new FogLayer(this.map, {
        clearRadius: this.settings.fogOfWarRadius || 1000,
        visible: this.settings.fogEnabled || false,
        mode: this.settings.fogOfWarMode || "points",
        api: this.api,
        controller: this.controller,
        tiledSource: tiledFog,
      })
      this.layers.fogLayer.add(pointsGeoJSON)
    } else {
      this.layers.fogLayer.update(pointsGeoJSON)
    }
    // Tiled fog reads the points MVT source — keep it loading even when the
    // Points toggle is off (paint-based hiding, see PointsMvtLayer).
    if (tiledFog && this.settings.fogEnabled) {
      this.layers.pointsMvtLayer?.setSourceKeepAlive(true)
    }
  }
}
