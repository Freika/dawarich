import { Controller } from '@hotwired/stimulus'
import maplibregl from 'maplibre-gl'
import { ApiClient } from 'maps_v2/services/api_client'
import { PointsLayer } from 'maps_v2/layers/points_layer'
import { RoutesLayer } from 'maps_v2/layers/routes_layer'
import { HeatmapLayer } from 'maps_v2/layers/heatmap_layer'
import { VisitsLayer } from 'maps_v2/layers/visits_layer'
import { PhotosLayer } from 'maps_v2/layers/photos_layer'
import { pointsToGeoJSON } from 'maps_v2/utils/geojson_transformers'
import { PopupFactory } from 'maps_v2/components/popup_factory'
import { VisitPopupFactory } from 'maps_v2/components/visit_popup'
import { PhotoPopupFactory } from 'maps_v2/components/photo_popup'
import { SettingsManager } from 'maps_v2/utils/settings_manager'

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

  connect() {
    this.loadSettings()
    this.initializeMap()
    this.initializeAPI()
    this.currentVisitFilter = 'all'
    this.loadMapData()
  }

  disconnect() {
    this.map?.remove()
  }

  /**
   * Load settings from localStorage
   */
  loadSettings() {
    this.settings = SettingsManager.getSettings()
  }

  /**
   * Initialize MapLibre map
   */
  initializeMap() {
    // Get map style URL from settings
    const styleUrl = this.getMapStyleUrl(this.settings.mapStyle)

    this.map = new maplibregl.Map({
      container: this.containerTarget,
      style: styleUrl,
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
    this.showLoading()

    try {
      // Fetch all points for selected month
      const points = await this.api.fetchAllPoints({
        start_at: this.startDateValue,
        end_at: this.endDateValue,
        onProgress: this.updateLoadingProgress.bind(this)
      })

      // Transform to GeoJSON for points
      const pointsGeoJSON = pointsToGeoJSON(points)

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
        photos = await this.api.fetchPhotos({
          start_at: this.startDateValue,
          end_at: this.endDateValue
        })
      } catch (error) {
        console.warn('Failed to fetch photos:', error)
        // Continue with empty photos array
      }

      const photosGeoJSON = this.photosToGeoJSON(photos)

      const addPhotosLayer = async () => {
        if (!this.photosLayer) {
          this.photosLayer = new PhotosLayer(this.map, {
            visible: this.settings.photosEnabled || false
          })
          await this.photosLayer.add(photosGeoJSON)
        } else {
          await this.photosLayer.update(photosGeoJSON)
        }
      }

      // Add all layers when style is ready
      // Note: Layer order matters - layers added first render below layers added later
      // Order: heatmap (bottom) -> routes -> visits -> photos -> points (top)
      const addAllLayers = async () => {
        addHeatmapLayer()  // Add heatmap first (renders at bottom)
        addRoutesLayer()   // Add routes second
        addVisitsLayer()   // Add visits third

        // Add photos layer with error handling (async, might fail loading images)
        try {
          await addPhotosLayer()  // Add photos fourth (async for image loading)
        } catch (error) {
          console.warn('Failed to add photos layer:', error)
        }

        addPointsLayer()   // Add points last (renders on top)

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

    } catch (error) {
      console.error('Failed to load map data:', error)
      alert('Failed to load location data. Please try again.')
    } finally {
      this.hideLoading()
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
   * Month selector changed
   */
  monthChanged(event) {
    const [year, month] = event.target.value.split('-')

    // Update date values
    this.startDateValue = `${year}-${month}-01T00:00:00Z`
    const lastDay = new Date(year, month, 0).getDate()
    this.endDateValue = `${year}-${month}-${lastDay}T23:59:59Z`

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
   * Get map style URL
   */
  getMapStyleUrl(styleName) {
    const styleUrls = {
      positron: 'https://basemaps.cartocdn.com/gl/positron-gl-style/style.json',
      'dark-matter': 'https://basemaps.cartocdn.com/gl/dark-matter-gl-style/style.json',
      voyager: 'https://basemaps.cartocdn.com/gl/voyager-gl-style/style.json'
    }

    return styleUrls[styleName] || styleUrls.positron
  }

  /**
   * Update map style from settings
   */
  updateMapStyle(event) {
    const style = event.target.value
    SettingsManager.updateSetting('mapStyle', style)

    const styleUrl = this.getMapStyleUrl(style)

    // Store current data
    const pointsData = this.pointsLayer?.data
    const routesData = this.routesLayer?.data
    const heatmapData = this.heatmapLayer?.data

    // Clear layer references
    this.pointsLayer = null
    this.routesLayer = null
    this.heatmapLayer = null

    this.map.setStyle(styleUrl)

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
      features: photos.map(photo => ({
        type: 'Feature',
        geometry: {
          type: 'Point',
          coordinates: [photo.longitude, photo.latitude]
        },
        properties: {
          id: photo.id,
          thumbnail_url: photo.thumbnail_url,
          url: photo.url,
          taken_at: photo.taken_at,
          camera: photo.camera,
          location_name: photo.location_name
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
}
