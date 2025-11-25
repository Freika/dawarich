import { Controller } from '@hotwired/stimulus'
import maplibregl from 'maplibre-gl'
import { ApiClient } from 'maps_v2/services/api_client'
import { PointsLayer } from 'maps_v2/layers/points_layer'
import { RoutesLayer } from 'maps_v2/layers/routes_layer'
import { HeatmapLayer } from 'maps_v2/layers/heatmap_layer'
import { VisitsLayer } from 'maps_v2/layers/visits_layer'
import { PhotosLayer } from 'maps_v2/layers/photos_layer'
import { AreasLayer } from 'maps_v2/layers/areas_layer'
import { TracksLayer } from 'maps_v2/layers/tracks_layer'
import { FogLayer } from 'maps_v2/layers/fog_layer'
import { FamilyLayer } from 'maps_v2/layers/family_layer'
import { pointsToGeoJSON } from 'maps_v2/utils/geojson_transformers'
import { PopupFactory } from 'maps_v2/components/popup_factory'
import { VisitPopupFactory } from 'maps_v2/components/visit_popup'
import { PhotoPopupFactory } from 'maps_v2/components/photo_popup'
import { SettingsManager } from 'maps_v2/utils/settings_manager'
import { createCircle } from 'maps_v2/utils/geometry'
import { Toast } from 'maps_v2/components/toast'
import { lazyLoader } from 'maps_v2/utils/lazy_loader'
import { ProgressiveLoader } from 'maps_v2/utils/progressive_loader'
import { performanceMonitor } from 'maps_v2/utils/performance_monitor'
import { CleanupHelper } from 'maps_v2/utils/cleanup_helper'
import { getMapStyle } from 'maps_v2/utils/style_manager'

/**
 * Main map controller for Maps V2
 * Phase 3: With heatmap and settings panel
 */
export default class extends Controller {
  static values = {
    apiKey: String,
    startDate: String,
    endDate: String
  }

  static targets = ['container', 'loading', 'loadingText', 'monthSelect', 'clusterToggle', 'settingsPanel', 'visitsSearch']

  async connect() {
    this.cleanup = new CleanupHelper()

    // Initialize settings manager with API key for backend sync
    SettingsManager.initialize(this.apiKeyValue)

    // Sync settings from backend (will fall back to localStorage if needed)
    await this.loadSettings()

    await this.initializeMap()
    this.initializeAPI()
    this.currentVisitFilter = 'all'

    // Format initial dates from backend to match V1 API format
    this.startDateValue = this.formatDateForAPI(new Date(this.startDateValue))
    this.endDateValue = this.formatDateForAPI(new Date(this.endDateValue))
    console.log('[Maps V2] Initial dates:', this.startDateValue, 'to', this.endDateValue)

    this.loadMapData()
  }

  disconnect() {
    this.cleanup.cleanup()
    this.map?.remove()
    performanceMonitor.logReport()
  }

  /**
   * Load settings (sync from backend and localStorage)
   */
  async loadSettings() {
    this.settings = await SettingsManager.sync()
    console.log('[Maps V2] Settings loaded:', this.settings)
  }

  /**
   * Initialize MapLibre map
   */
  async initializeMap() {
    // Get map style from local files (async)
    const style = await getMapStyle(this.settings.mapStyle)

    this.map = new maplibregl.Map({
      container: this.containerTarget,
      style: style,
      center: [0, 0],
      zoom: 2
    })

    // Add navigation controls
    this.map.addControl(new maplibregl.NavigationControl(), 'top-right')

    // Setup click handler for points
    this.map.on('click', 'points', this.handlePointClick.bind(this))

    // Change cursor on hover
    this.map.on('mouseenter', 'points', () => {
      this.map.getCanvas().style.cursor = 'pointer'
    })
    this.map.on('mouseleave', 'points', () => {
      this.map.getCanvas().style.cursor = ''
    })
  }

  /**
   * Initialize API client
   */
  initializeAPI() {
    this.api = new ApiClient(this.apiKeyValue)
  }

  /**
   * Load points data from API
   */
  async loadMapData() {
    performanceMonitor.mark('load-map-data')
    this.showLoading()

    try {
      // Fetch all points for selected month
      performanceMonitor.mark('fetch-points')
      const points = await this.api.fetchAllPoints({
        start_at: this.startDateValue,
        end_at: this.endDateValue,
        onProgress: this.updateLoadingProgress.bind(this)
      })
      performanceMonitor.measure('fetch-points')

      // Transform to GeoJSON for points
      performanceMonitor.mark('transform-geojson')
      const pointsGeoJSON = pointsToGeoJSON(points)
      performanceMonitor.measure('transform-geojson')

      // Create routes from points
      const routesGeoJSON = RoutesLayer.pointsToRoutes(points)

      // Define all layer add functions
      const addRoutesLayer = () => {
        if (!this.routesLayer) {
          this.routesLayer = new RoutesLayer(this.map)
          this.routesLayer.add(routesGeoJSON)
        } else {
          this.routesLayer.update(routesGeoJSON)
        }
      }

      const addPointsLayer = () => {
        if (!this.pointsLayer) {
          this.pointsLayer = new PointsLayer(this.map)
          this.pointsLayer.add(pointsGeoJSON)
        } else {
          this.pointsLayer.update(pointsGeoJSON)
        }
      }

      const addHeatmapLayer = () => {
        if (!this.heatmapLayer) {
          this.heatmapLayer = new HeatmapLayer(this.map, {
            visible: this.settings.heatmapEnabled
          })
          this.heatmapLayer.add(pointsGeoJSON)
        } else {
          this.heatmapLayer.update(pointsGeoJSON)
        }
      }

      // Load visits
      let visits = []
      try {
        visits = await this.api.fetchVisits({
          start_at: this.startDateValue,
          end_at: this.endDateValue
        })
      } catch (error) {
        console.warn('Failed to fetch visits:', error)
        // Continue with empty visits array
      }

      const visitsGeoJSON = this.visitsToGeoJSON(visits)
      this.allVisits = visits // Store for filtering

      const addVisitsLayer = () => {
        if (!this.visitsLayer) {
          this.visitsLayer = new VisitsLayer(this.map, {
            visible: this.settings.visitsEnabled || false
          })
          this.visitsLayer.add(visitsGeoJSON)
        } else {
          this.visitsLayer.update(visitsGeoJSON)
        }
      }

      // Load photos
      let photos = []
      try {
        console.log('[Photos] Fetching photos from:', this.startDateValue, 'to', this.endDateValue)
        photos = await this.api.fetchPhotos({
          start_at: this.startDateValue,
          end_at: this.endDateValue
        })
        console.log('[Photos] Fetched photos:', photos.length, 'photos')
        console.log('[Photos] Sample photo:', photos[0])
      } catch (error) {
        console.error('[Photos] Failed to fetch photos:', error)
        // Continue with empty photos array
      }

      const photosGeoJSON = this.photosToGeoJSON(photos)
      console.log('[Photos] Converted to GeoJSON:', photosGeoJSON.features.length, 'features')
      console.log('[Photos] Sample feature:', photosGeoJSON.features[0])

      const addPhotosLayer = async () => {
        console.log('[Photos] Adding photos layer, visible:', this.settings.photosEnabled)
        if (!this.photosLayer) {
          this.photosLayer = new PhotosLayer(this.map, {
            visible: this.settings.photosEnabled || false
          })
          console.log('[Photos] Created new PhotosLayer instance')
          await this.photosLayer.add(photosGeoJSON)
          console.log('[Photos] Added photos to layer')
        } else {
          console.log('[Photos] Updating existing PhotosLayer')
          await this.photosLayer.update(photosGeoJSON)
          console.log('[Photos] Updated photos layer')
        }
      }

      // Load areas
      let areas = []
      try {
        areas = await this.api.fetchAreas()
      } catch (error) {
        console.warn('Failed to fetch areas:', error)
        // Continue with empty areas array
      }

      const areasGeoJSON = this.areasToGeoJSON(areas)

      const addAreasLayer = () => {
        if (!this.areasLayer) {
          this.areasLayer = new AreasLayer(this.map, {
            visible: this.settings.areasEnabled || false
          })
          this.areasLayer.add(areasGeoJSON)
        } else {
          this.areasLayer.update(areasGeoJSON)
        }
      }

      // Load tracks - DISABLED: Backend API not yet implemented
      // TODO: Re-enable when /api/v1/tracks endpoint is created
      const tracks = []
      const tracksGeoJSON = this.tracksToGeoJSON(tracks)

      const addTracksLayer = () => {
        if (!this.tracksLayer) {
          this.tracksLayer = new TracksLayer(this.map, {
            visible: this.settings.tracksEnabled || false
          })
          this.tracksLayer.add(tracksGeoJSON)
        } else {
          this.tracksLayer.update(tracksGeoJSON)
        }
      }

      // Add scratch layer (lazy loaded)
      const addScratchLayer = async () => {
        try {
          if (!this.scratchLayer && this.settings.scratchEnabled) {
            const ScratchLayer = await lazyLoader.loadLayer('scratch')
            this.scratchLayer = new ScratchLayer(this.map, {
              visible: true,
              apiClient: this.api // Pass API client for authenticated requests
            })
            await this.scratchLayer.add(pointsGeoJSON)
          } else if (this.scratchLayer) {
            await this.scratchLayer.update(pointsGeoJSON)
          }
        } catch (error) {
          console.warn('Failed to load scratch layer:', error)
        }
      }

      // Add family layer (for real-time family locations)
      const addFamilyLayer = () => {
        if (!this.familyLayer) {
          this.familyLayer = new FamilyLayer(this.map, {
            visible: false // Initially hidden, shown when family locations arrive via ActionCable
          })
          this.familyLayer.add({ type: 'FeatureCollection', features: [] })
        }
      }

      // Add all layers when style is ready
      // Note: Layer order matters - layers added first render below layers added later
      // Order: scratch (bottom) -> heatmap -> areas -> tracks -> routes -> visits -> photos -> family -> points (top) -> fog (canvas overlay)
      const addAllLayers = async () => {
        performanceMonitor.mark('add-layers')

        await addScratchLayer() // Add scratch first (renders at bottom) - lazy loaded
        addHeatmapLayer()      // Add heatmap second
        addAreasLayer()        // Add areas third
        addTracksLayer()       // Add tracks fourth
        addRoutesLayer()       // Add routes fifth
        addVisitsLayer()       // Add visits sixth

        // Add photos layer with error handling (async, might fail loading images)
        try {
          await addPhotosLayer()  // Add photos seventh (async for image loading)
        } catch (error) {
          console.warn('Failed to add photos layer:', error)
        }

        addFamilyLayer()   // Add family layer (real-time family locations)
        addPointsLayer()   // Add points last (renders on top)

        // Add fog layer (canvas overlay, separate from MapLibre layers)
        // Always create fog layer for backward compatibility
        if (!this.fogLayer) {
          this.fogLayer = new FogLayer(this.map, {
            clearRadius: 1000,
            visible: this.settings.fogEnabled || false
          })
          this.fogLayer.add(pointsGeoJSON)
        } else {
          this.fogLayer.update(pointsGeoJSON)
        }

        performanceMonitor.measure('add-layers')

        // Add click handlers for visits and photos
        this.map.on('click', 'visits', this.handleVisitClick.bind(this))
        this.map.on('click', 'photos', this.handlePhotoClick.bind(this))

        // Change cursor on hover
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
      }

      // Use 'load' event which fires when map is fully initialized
      // This is more reliable than 'style.load'
      if (this.map.loaded()) {
        await addAllLayers()
      } else {
        this.map.once('load', async () => {
          await addAllLayers()
        })
      }

      // Fit map to data bounds
      if (points.length > 0) {
        this.fitMapToBounds(pointsGeoJSON)
      }

      // Show success toast
      Toast.success(`Loaded ${points.length} location ${points.length === 1 ? 'point' : 'points'}`)

    } catch (error) {
      console.error('Failed to load map data:', error)
      Toast.error('Failed to load location data. Please try again.')
    } finally {
      this.hideLoading()
      const duration = performanceMonitor.measure('load-map-data')
      console.log(`[Performance] Map data loaded in ${duration}ms`)
    }
  }

  /**
   * Handle point click
   */
  handlePointClick(e) {
    const feature = e.features[0]
    const coordinates = feature.geometry.coordinates.slice()
    const properties = feature.properties

    // Create popup
    new maplibregl.Popup()
      .setLngLat(coordinates)
      .setHTML(PopupFactory.createPointPopup(properties))
      .addTo(this.map)
  }

  /**
   * Fit map to data bounds
   */
  fitMapToBounds(geojson) {
    const coordinates = geojson.features.map(f => f.geometry.coordinates)

    const bounds = coordinates.reduce((bounds, coord) => {
      return bounds.extend(coord)
    }, new maplibregl.LngLatBounds(coordinates[0], coordinates[0]))

    this.map.fitBounds(bounds, {
      padding: 50,
      maxZoom: 15
    })
  }

  /**
   * Format date for API requests (matching V1 format)
   * Format: "YYYY-MM-DDTHH:MM" (e.g., "2025-10-15T00:00", "2025-10-15T23:59")
   */
  formatDateForAPI(date) {
    const pad = (n) => String(n).padStart(2, '0')
    const year = date.getFullYear()
    const month = pad(date.getMonth() + 1)
    const day = pad(date.getDate())
    const hours = pad(date.getHours())
    const minutes = pad(date.getMinutes())

    return `${year}-${month}-${day}T${hours}:${minutes}`
  }

  /**
   * Month selector changed
   */
  monthChanged(event) {
    const [year, month] = event.target.value.split('-')

    const startDate = new Date(year, month - 1, 1, 0, 0, 0)
    const lastDay = new Date(year, month, 0).getDate()
    const endDate = new Date(year, month - 1, lastDay, 23, 59, 0)

    this.startDateValue = this.formatDateForAPI(startDate)
    this.endDateValue = this.formatDateForAPI(endDate)

    console.log('[Maps V2] Date range changed:', this.startDateValue, 'to', this.endDateValue)

    // Reload data
    this.loadMapData()
  }

  /**
   * Show loading indicator
   */
  showLoading() {
    this.loadingTarget.classList.remove('hidden')
  }

  /**
   * Hide loading indicator
   */
  hideLoading() {
    this.loadingTarget.classList.add('hidden')
  }

  /**
   * Update loading progress
   */
  updateLoadingProgress({ loaded, totalPages, progress }) {
    if (this.hasLoadingTextTarget) {
      const percentage = Math.round(progress * 100)
      this.loadingTextTarget.textContent = `Loading... ${percentage}%`
    }
  }

  /**
   * Toggle layer visibility
   */
  toggleLayer(event) {
    const button = event.currentTarget
    const layerName = button.dataset.layer

    // Get the layer instance
    const layer = this[`${layerName}Layer`]
    if (!layer) return

    // Toggle visibility
    layer.toggle()

    // Update button style
    if (layer.visible) {
      button.classList.add('btn-primary')
      button.classList.remove('btn-outline')
    } else {
      button.classList.remove('btn-primary')
      button.classList.add('btn-outline')
    }
  }

  /**
   * Toggle point clustering
   */
  toggleClustering(event) {
    if (!this.pointsLayer) return

    const button = event.currentTarget

    // Toggle clustering state
    const newClusteringState = !this.pointsLayer.clusteringEnabled
    this.pointsLayer.toggleClustering(newClusteringState)

    // Update button style to reflect state
    if (newClusteringState) {
      button.classList.add('btn-primary')
      button.classList.remove('btn-outline')
    } else {
      button.classList.remove('btn-primary')
      button.classList.add('btn-outline')
    }

    // Save setting
    SettingsManager.updateSetting('clustering', newClusteringState)
  }

  /**
   * Toggle settings panel
   */
  toggleSettings() {
    if (this.hasSettingsPanelTarget) {
      this.settingsPanelTarget.classList.toggle('open')
    }
  }

  /**
   * Update map style from settings
   */
  async updateMapStyle(event) {
    const styleName = event.target.value
    SettingsManager.updateSetting('mapStyle', styleName)

    const style = await getMapStyle(styleName)

    // Store current data
    const pointsData = this.pointsLayer?.data
    const routesData = this.routesLayer?.data
    const heatmapData = this.heatmapLayer?.data

    // Clear layer references
    this.pointsLayer = null
    this.routesLayer = null
    this.heatmapLayer = null

    this.map.setStyle(style)

    // Reload layers after style change
    this.map.once('style.load', () => {
      console.log('Style loaded, reloading map data')
      this.loadMapData()
    })
  }

  /**
   * Toggle heatmap visibility
   */
  toggleHeatmap(event) {
    const enabled = event.target.checked
    SettingsManager.updateSetting('heatmapEnabled', enabled)

    if (this.heatmapLayer) {
      if (enabled) {
        this.heatmapLayer.show()
      } else {
        this.heatmapLayer.hide()
      }
    }
  }

  /**
   * Reset settings to defaults
   */
  resetSettings() {
    if (confirm('Reset all settings to defaults? This will reload the page.')) {
      SettingsManager.resetToDefaults()
      window.location.reload()
    }
  }

  /**
   * Convert visits to GeoJSON
   */
  visitsToGeoJSON(visits) {
    return {
      type: 'FeatureCollection',
      features: visits.map(visit => ({
        type: 'Feature',
        geometry: {
          type: 'Point',
          coordinates: [visit.place.longitude, visit.place.latitude]
        },
        properties: {
          id: visit.id,
          name: visit.name,
          place_name: visit.place?.name,
          status: visit.status,
          started_at: visit.started_at,
          ended_at: visit.ended_at,
          duration: visit.duration
        }
      }))
    }
  }

  /**
   * Convert photos to GeoJSON
   */
  photosToGeoJSON(photos) {
    return {
      type: 'FeatureCollection',
      features: photos.map(photo => {
        // Construct thumbnail URL
        const thumbnailUrl = `/api/v1/photos/${photo.id}/thumbnail.jpg?api_key=${this.api.apiKey}&source=${photo.source}`

        return {
          type: 'Feature',
          geometry: {
            type: 'Point',
            coordinates: [photo.longitude, photo.latitude]
          },
          properties: {
            id: photo.id,
            thumbnail_url: thumbnailUrl,
            taken_at: photo.localDateTime,
            filename: photo.originalFileName,
            city: photo.city,
            state: photo.state,
            country: photo.country,
            type: photo.type,
            source: photo.source
          }
        }
      })
    }
  }

  /**
   * Convert areas to GeoJSON
   * Backend returns circular areas with latitude, longitude, radius
   */
  areasToGeoJSON(areas) {
    return {
      type: 'FeatureCollection',
      features: areas.map(area => {
        // Create circle polygon from center and radius
        const center = [area.longitude, area.latitude]
        const coordinates = createCircle(center, area.radius)

        return {
          type: 'Feature',
          geometry: {
            type: 'Polygon',
            coordinates: [coordinates]
          },
          properties: {
            id: area.id,
            name: area.name,
            color: area.color || '#3b82f6',
            radius: area.radius
          }
        }
      })
    }
  }

  /**
   * Convert tracks to GeoJSON
   */
  tracksToGeoJSON(tracks) {
    return {
      type: 'FeatureCollection',
      features: tracks.map(track => ({
        type: 'Feature',
        geometry: {
          type: 'LineString',
          coordinates: track.coordinates
        },
        properties: {
          id: track.id,
          name: track.name,
          color: track.color || '#8b5cf6'
        }
      }))
    }
  }

  /**
   * Handle visit click
   */
  handleVisitClick(e) {
    const feature = e.features[0]
    const coordinates = feature.geometry.coordinates.slice()
    const properties = feature.properties

    new maplibregl.Popup()
      .setLngLat(coordinates)
      .setHTML(VisitPopupFactory.createVisitPopup(properties))
      .addTo(this.map)
  }

  /**
   * Handle photo click
   */
  handlePhotoClick(e) {
    const feature = e.features[0]
    const coordinates = feature.geometry.coordinates.slice()
    const properties = feature.properties

    new maplibregl.Popup()
      .setLngLat(coordinates)
      .setHTML(PhotoPopupFactory.createPhotoPopup(properties))
      .addTo(this.map)
  }

  /**
   * Toggle visits layer
   */
  toggleVisits(event) {
    const enabled = event.target.checked
    SettingsManager.updateSetting('visitsEnabled', enabled)

    if (this.visitsLayer) {
      if (enabled) {
        this.visitsLayer.show()
        // Show visits search
        if (this.hasVisitsSearchTarget) {
          this.visitsSearchTarget.style.display = 'block'
        }
      } else {
        this.visitsLayer.hide()
        // Hide visits search
        if (this.hasVisitsSearchTarget) {
          this.visitsSearchTarget.style.display = 'none'
        }
      }
    }
  }

  /**
   * Toggle photos layer
   */
  togglePhotos(event) {
    const enabled = event.target.checked
    SettingsManager.updateSetting('photosEnabled', enabled)

    if (this.photosLayer) {
      if (enabled) {
        this.photosLayer.show()
      } else {
        this.photosLayer.hide()
      }
    }
  }

  /**
   * Search visits
   */
  searchVisits(event) {
    const searchTerm = event.target.value.toLowerCase()
    this.filterAndUpdateVisits(searchTerm, this.currentVisitFilter)
  }

  /**
   * Filter visits by status
   */
  filterVisits(event) {
    const filter = event.target.value
    this.currentVisitFilter = filter
    const searchTerm = document.getElementById('visits-search')?.value.toLowerCase() || ''
    this.filterAndUpdateVisits(searchTerm, filter)
  }

  /**
   * Filter and update visits display
   */
  filterAndUpdateVisits(searchTerm, statusFilter) {
    if (!this.allVisits || !this.visitsLayer) return

    const filtered = this.allVisits.filter(visit => {
      // Apply search
      const matchesSearch = !searchTerm ||
        visit.name?.toLowerCase().includes(searchTerm) ||
        visit.place?.name?.toLowerCase().includes(searchTerm)

      // Apply status filter
      const matchesStatus = statusFilter === 'all' || visit.status === statusFilter

      return matchesSearch && matchesStatus
    })

    const geojson = this.visitsToGeoJSON(filtered)
    this.visitsLayer.update(geojson)
  }

  /**
   * Toggle areas layer
   */
  toggleAreas(event) {
    const enabled = event.target.checked
    SettingsManager.updateSetting('areasEnabled', enabled)

    if (this.areasLayer) {
      if (enabled) {
        this.areasLayer.show()
      } else {
        this.areasLayer.hide()
      }
    }
  }

  /**
   * Toggle tracks layer
   */
  toggleTracks(event) {
    const enabled = event.target.checked
    SettingsManager.updateSetting('tracksEnabled', enabled)

    if (this.tracksLayer) {
      if (enabled) {
        this.tracksLayer.show()
      } else {
        this.tracksLayer.hide()
      }
    }
  }

  /**
   * Toggle fog of war layer
   */
  toggleFog(event) {
    const enabled = event.target.checked
    SettingsManager.updateSetting('fogEnabled', enabled)

    if (this.fogLayer) {
      this.fogLayer.toggle(enabled)
    } else {
      console.warn('Fog layer not yet initialized')
    }
  }

  /**
   * Toggle scratch map layer
   */
  async toggleScratch(event) {
    const enabled = event.target.checked
    SettingsManager.updateSetting('scratchEnabled', enabled)

    try {
      if (!this.scratchLayer && enabled) {
        // Lazy load scratch layer
        const ScratchLayer = await lazyLoader.loadLayer('scratch')
        this.scratchLayer = new ScratchLayer(this.map, {
          visible: true,
          apiClient: this.api
        })
        const pointsData = this.pointsLayer?.data || { type: 'FeatureCollection', features: [] }
        await this.scratchLayer.add(pointsData)
      } else if (this.scratchLayer) {
        if (enabled) {
          this.scratchLayer.show()
        } else {
          this.scratchLayer.hide()
        }
      }
    } catch (error) {
      console.error('Failed to toggle scratch layer:', error)
      Toast.error('Failed to load scratch layer')
    }
  }
}
