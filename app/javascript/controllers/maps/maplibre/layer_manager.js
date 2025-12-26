import { PointsLayer } from 'maps_maplibre/layers/points_layer'
import { RoutesLayer } from 'maps_maplibre/layers/routes_layer'
import { HeatmapLayer } from 'maps_maplibre/layers/heatmap_layer'
import { VisitsLayer } from 'maps_maplibre/layers/visits_layer'
import { PhotosLayer } from 'maps_maplibre/layers/photos_layer'
import { AreasLayer } from 'maps_maplibre/layers/areas_layer'
import { TracksLayer } from 'maps_maplibre/layers/tracks_layer'
import { PlacesLayer } from 'maps_maplibre/layers/places_layer'
import { FogLayer } from 'maps_maplibre/layers/fog_layer'
import { FamilyLayer } from 'maps_maplibre/layers/family_layer'
import { RecentPointLayer } from 'maps_maplibre/layers/recent_point_layer'
import { lazyLoader } from 'maps_maplibre/utils/lazy_loader'
import { performanceMonitor } from 'maps_maplibre/utils/performance_monitor'

/**
 * Manages all map layers lifecycle and visibility
 */
export class LayerManager {
  constructor(map, settings, api) {
    this.map = map
    this.settings = settings
    this.api = api
    this.layers = {}
  }

  /**
   * Add or update all layers with provided data
   */
  async addAllLayers(pointsGeoJSON, routesGeoJSON, visitsGeoJSON, photosGeoJSON, areasGeoJSON, tracksGeoJSON, placesGeoJSON) {
    performanceMonitor.mark('add-layers')

    // Layer order matters - layers added first render below layers added later
    // Order: scratch (bottom) -> heatmap -> areas -> tracks -> routes -> visits -> places -> photos -> family -> points -> recent-point (top) -> fog (canvas overlay)

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
      console.warn('Failed to add photos layer:', error)
    }

    this._addFamilyLayer()
    this._addPointsLayer(pointsGeoJSON)
    this._addRecentPointLayer()
    this._addFogLayer(pointsGeoJSON)

    performanceMonitor.measure('add-layers')
  }

  /**
   * Setup event handlers for layer interactions
   */
  setupLayerEventHandlers(handlers) {
    // Click handlers
    this.map.on('click', 'points', handlers.handlePointClick)
    this.map.on('click', 'visits', handlers.handleVisitClick)
    this.map.on('click', 'photos', handlers.handlePhotoClick)
    this.map.on('click', 'places', handlers.handlePlaceClick)
    // Areas have multiple layers (fill, outline, labels)
    this.map.on('click', 'areas-fill', handlers.handleAreaClick)
    this.map.on('click', 'areas-outline', handlers.handleAreaClick)
    this.map.on('click', 'areas-labels', handlers.handleAreaClick)

    // Cursor change on hover
    this.map.on('mouseenter', 'points', () => {
      this.map.getCanvas().style.cursor = 'pointer'
    })
    this.map.on('mouseleave', 'points', () => {
      this.map.getCanvas().style.cursor = ''
    })
    this.map.on('mouseenter', 'visits', () => {
      this.map.getCanvas().style.cursor = 'pointer'
    })
    this.map.on('mouseleave', 'visits', () => {
      this.map.getCanvas().style.cursor = ''
    })
    this.map.on('mouseenter', 'photos', () => {
      this.map.getCanvas().style.cursor = 'pointer'
    })
    this.map.on('mouseleave', 'photos', () => {
      this.map.getCanvas().style.cursor = ''
    })
    this.map.on('mouseenter', 'places', () => {
      this.map.getCanvas().style.cursor = 'pointer'
    })
    this.map.on('mouseleave', 'places', () => {
      this.map.getCanvas().style.cursor = ''
    })
    // Areas hover handlers for all sub-layers
    const areaLayers = ['areas-fill', 'areas-outline', 'areas-labels']
    areaLayers.forEach(layerId => {
      // Only add handlers if layer exists
      if (this.map.getLayer(layerId)) {
        this.map.on('mouseenter', layerId, () => {
          this.map.getCanvas().style.cursor = 'pointer'
        })
        this.map.on('mouseleave', layerId, () => {
          this.map.getCanvas().style.cursor = ''
        })
      }
    })
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
   * Clear all layer references (for style changes)
   */
  clearLayerReferences() {
    this.layers = {}
  }

  // Private methods for individual layer management

  async _addScratchLayer(pointsGeoJSON) {
    try {
      if (!this.layers.scratchLayer && this.settings.scratchEnabled) {
        const ScratchLayer = await lazyLoader.loadLayer('scratch')
        this.layers.scratchLayer = new ScratchLayer(this.map, {
          visible: true,
          apiClient: this.api
        })
        await this.layers.scratchLayer.add(pointsGeoJSON)
      } else if (this.layers.scratchLayer) {
        await this.layers.scratchLayer.update(pointsGeoJSON)
      }
    } catch (error) {
      console.warn('Failed to load scratch layer:', error)
    }
  }

  _addHeatmapLayer(pointsGeoJSON) {
    if (!this.layers.heatmapLayer) {
      this.layers.heatmapLayer = new HeatmapLayer(this.map, {
        visible: this.settings.heatmapEnabled
      })
      this.layers.heatmapLayer.add(pointsGeoJSON)
    } else {
      this.layers.heatmapLayer.update(pointsGeoJSON)
    }
  }

  _addAreasLayer(areasGeoJSON) {
    if (!this.layers.areasLayer) {
      this.layers.areasLayer = new AreasLayer(this.map, {
        visible: this.settings.areasEnabled || false
      })
      this.layers.areasLayer.add(areasGeoJSON)
    } else {
      this.layers.areasLayer.update(areasGeoJSON)
    }
  }

  _addTracksLayer(tracksGeoJSON) {
    if (!this.layers.tracksLayer) {
      this.layers.tracksLayer = new TracksLayer(this.map, {
        visible: this.settings.tracksEnabled || false
      })
      this.layers.tracksLayer.add(tracksGeoJSON)
    } else {
      this.layers.tracksLayer.update(tracksGeoJSON)
    }
  }

  _addRoutesLayer(routesGeoJSON) {
    if (!this.layers.routesLayer) {
      this.layers.routesLayer = new RoutesLayer(this.map, {
        visible: this.settings.routesVisible !== false // Default true unless explicitly false
      })
      this.layers.routesLayer.add(routesGeoJSON)
    } else {
      this.layers.routesLayer.update(routesGeoJSON)
    }
  }

  _addVisitsLayer(visitsGeoJSON) {
    if (!this.layers.visitsLayer) {
      this.layers.visitsLayer = new VisitsLayer(this.map, {
        visible: this.settings.visitsEnabled || false
      })
      this.layers.visitsLayer.add(visitsGeoJSON)
    } else {
      this.layers.visitsLayer.update(visitsGeoJSON)
    }
  }

  _addPlacesLayer(placesGeoJSON) {
    if (!this.layers.placesLayer) {
      this.layers.placesLayer = new PlacesLayer(this.map, {
        visible: this.settings.placesEnabled || false
      })
      this.layers.placesLayer.add(placesGeoJSON)
    } else {
      this.layers.placesLayer.update(placesGeoJSON)
    }
  }

  async _addPhotosLayer(photosGeoJSON) {
    console.log('[Photos] Adding photos layer, visible:', this.settings.photosEnabled)
    if (!this.layers.photosLayer) {
      this.layers.photosLayer = new PhotosLayer(this.map, {
        visible: this.settings.photosEnabled || false
      })
      console.log('[Photos] Created new PhotosLayer instance')
      await this.layers.photosLayer.add(photosGeoJSON)
      console.log('[Photos] Added photos to layer')
    } else {
      console.log('[Photos] Updating existing PhotosLayer')
      await this.layers.photosLayer.update(photosGeoJSON)
      console.log('[Photos] Updated photos layer')
    }
  }

  _addFamilyLayer() {
    if (!this.layers.familyLayer) {
      this.layers.familyLayer = new FamilyLayer(this.map, {
        visible: false // Initially hidden, shown when family locations arrive via ActionCable
      })
      this.layers.familyLayer.add({ type: 'FeatureCollection', features: [] })
    }
  }

  _addPointsLayer(pointsGeoJSON) {
    if (!this.layers.pointsLayer) {
      this.layers.pointsLayer = new PointsLayer(this.map, {
        visible: this.settings.pointsVisible !== false, // Default true unless explicitly false
        apiClient: this.api,
        layerManager: this
      })
      this.layers.pointsLayer.add(pointsGeoJSON)
    } else {
      this.layers.pointsLayer.update(pointsGeoJSON)
    }
  }

  _addRecentPointLayer() {
    if (!this.layers.recentPointLayer) {
      this.layers.recentPointLayer = new RecentPointLayer(this.map, {
        visible: false // Initially hidden, shown only when live mode is enabled
      })
      this.layers.recentPointLayer.add({ type: 'FeatureCollection', features: [] })
    }
  }

  _addFogLayer(pointsGeoJSON) {
    // Always create fog layer for backward compatibility
    if (!this.layers.fogLayer) {
      this.layers.fogLayer = new FogLayer(this.map, {
        clearRadius: this.settings.fogOfWarRadius || 1000,
        visible: this.settings.fogEnabled || false
      })
      this.layers.fogLayer.add(pointsGeoJSON)
    } else {
      this.layers.fogLayer.update(pointsGeoJSON)
    }
  }
}
