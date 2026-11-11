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
import { layerEvents } from "./layer_events"

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
    // Photos load before tile layers, so raise their clusters above them.
    this.layers.photosLayer?.raiseAbove("points-mvt")
    this._addRecentPointLayer()
    this._addReplayMarkerLayer()
    this._addFogLayer()
    // Membership may scan a large history. The blank-filter Scratch source
    // attaches below the overlays when ready, without holding up tile layers.
    void this._addScratchLayer()

    performanceMonitor.measure("add-layers")
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

  /** Build the layer on first use, otherwise hand it the new data. */
  _addOrUpdate(key, create, data) {
    if (this.layers[key]) return this.layers[key].update(data)
    this.layers[key] = create()
    return this.layers[key].add(data)
  }

  /** Build a layer that starts empty and is filled by its own owner. */
  _addOnce(key, create) {
    if (this.layers[key]) return
    this.layers[key] = create()
    this.layers[key].add({ type: "FeatureCollection", features: [] })
  }

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
      loadingBadge: this.controller?.loadingBadge,
    })
    this.layers.hexagonsLayer.add({ type: "FeatureCollection", features: [] })
    return this.layers.hexagonsLayer
  }

  _addTracksLayer(tracksGeoJSON) {
    this._addOrUpdate(
      "tracksLayer",
      () =>
        new TracksLayer(this.map, {
          visible: this.settings.tracksEnabled || false,
        }),
      tracksGeoJSON,
    )
  }

  _addFlightsLayer(flightsGeoJSON) {
    this._addOrUpdate(
      "flightsLayer",
      () =>
        new FlightsLayer(this.map, {
          visible: this.settings.flightsEnabled || false,
          style: this.settings.mapStyle || "light",
        }),
      flightsGeoJSON,
    )
  }

  _addVisitsLayer(visitsGeoJSON) {
    this._addOrUpdate(
      "visitsLayer",
      () =>
        new VisitsLayer(this.map, {
          visible: this.settings.visitsEnabled || false,
        }),
      visitsGeoJSON,
    )
  }

  _addPlacesLayer(placesGeoJSON) {
    if (!this.layers.placesLayer) {
      this.layers.placesLayer = new PlacesLayer(this.map, {
        visible: this.settings.placesEnabled || false,
        boundariesVisible: this.settings.placeBoundariesEnabled || false,
      })
      this.layers.placesLayer.add(placesGeoJSON)
      if (this.map.getLayer("visits")) {
        this.map.moveLayer("places-radius-fill", "visits")
        this.map.moveLayer("places-radius-outline", "visits")
      }
    } else {
      this.layers.placesLayer.update(placesGeoJSON)
    }
  }

  async _addPhotosLayer(photosGeoJSON) {
    await this._addOrUpdate(
      "photosLayer",
      () =>
        new PhotosLayer(this.map, {
          visible: this.settings.photosEnabled || false,
          timezone: this.settings.timezone,
        }),
      photosGeoJSON,
    )
  }

  _addFamilyLayer() {
    this._addOnce(
      "familyLayer",
      () =>
        new FamilyLayer(this.map, {
          visible: this.settings.familyEnabled || false,
        }),
    )
  }

  _addAnomaliesLayer() {
    this._addOnce(
      "anomaliesLayer",
      () =>
        new AnomaliesLayer(this.map, {
          visible: false,
          apiClient: this.api,
          timezone: this.settings.timezone,
        }),
    )
  }

  // Tile-backed canonical Tracks layer; added below points so circles stay on
  // top of track lines.
  _addTracksMvtLayer() {
    if (!this.layers.tracksMvtLayer) {
      this.layers.tracksMvtLayer = new TracksMvtLayer(this.map, {
        tracksEnabled: this.settings.tracksEnabled === true,
        trackColor: SettingsManager.getSetting("trackColor"),
        speedColoring:
          SettingsManager.getSetting("speedColoredRoutes") === true,
        speedColorScale: SettingsManager.getSetting("speedColorScale"),
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
        // An empty period already explains itself on the map; the toast is
        // for points that have no tracks yet.
        onEmptyTracks: async () => {
          const statistics = this.controller?.rangeStatistics
          await statistics?.pending?.catch(() => {})
          if (statistics?.data?.points === 0) return
          Toast.info(translate("messages.tracks_pending"))
        },
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
        hoverTitle: translate("live_map.your_position"),
      })
      this.layers.recentPointLayer.add({
        type: "FeatureCollection",
        features: [],
      })
      if (this.controller?.hasCurrentPositionValue) {
        const position = this.controller.currentPositionValue
        this.layers.recentPointLayer.updateRecentPoint(
          position.longitude,
          position.latitude,
          { timestamp: position.timestamp },
        )
      }
    }
  }

  _addReplayMarkerLayer() {
    // Hidden until a replay starts.
    this._addOnce(
      "replayMarkerLayer",
      () => new ReplayMarkerLayer(this.map, { visible: false }),
    )
  }

  _addFogLayer() {
    // Always create fog layer for backward compatibility
    if (!this.layers.fogLayer) {
      this.layers.fogLayer = new FogLayer(this.map, {
        visible: this.settings.fogEnabled || false,
        api: this.api,
        dateRange: () => ({
          startAt: this.controller.startDateValue,
          endAt: this.controller.endDateValue,
        }),
        snapshotId: this.controller.explorationSnapshotValue,
        statusMessages: this.controller.explorationMessagesValue,
      })
      this.layers.fogLayer.add()
    } else {
      this.layers.fogLayer.update()
    }
  }
}

Object.assign(LayerManager.prototype, layerEvents)
