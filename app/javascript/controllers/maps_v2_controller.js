import { Controller } from '@hotwired/stimulus'
import maplibregl from 'maplibre-gl'
import { ApiClient } from 'maps_v2/services/api_client'
import { SettingsManager } from 'maps_v2/utils/settings_manager'
import { Toast } from 'maps_v2/components/toast'
import { performanceMonitor } from 'maps_v2/utils/performance_monitor'
import { CleanupHelper } from 'maps_v2/utils/cleanup_helper'
import { getMapStyle } from 'maps_v2/utils/style_manager'
import { LayerManager } from './maps_v2/layer_manager'
import { DataLoader } from './maps_v2/data_loader'
import { EventHandlers } from './maps_v2/event_handlers'
import { FilterManager } from './maps_v2/filter_manager'
import { DateManager } from './maps_v2/date_manager'
import { lazyLoader } from 'maps_v2/utils/lazy_loader'

/**
 * Main map controller for Maps V2
 * Coordinates between different managers and handles UI interactions
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

    // Initialize managers
    this.layerManager = new LayerManager(this.map, this.settings, this.api)
    this.dataLoader = new DataLoader(this.api, this.apiKeyValue)
    this.eventHandlers = new EventHandlers(this.map)
    this.filterManager = new FilterManager(this.dataLoader)

    // Format initial dates from backend to match V1 API format
    this.startDateValue = DateManager.formatDateForAPI(new Date(this.startDateValue))
    this.endDateValue = DateManager.formatDateForAPI(new Date(this.endDateValue))
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
  }

  /**
   * Initialize API client
   */
  initializeAPI() {
    this.api = new ApiClient(this.apiKeyValue)
  }

  /**
   * Load map data from API
   */
  async loadMapData() {
    performanceMonitor.mark('load-map-data')
    this.showLoading()

    try {
      // Fetch all map data
      const data = await this.dataLoader.fetchMapData(
        this.startDateValue,
        this.endDateValue,
        this.updateLoadingProgress.bind(this)
      )

      // Store visits for filtering
      this.filterManager.setAllVisits(data.visits)

      // Add all layers when style is ready
      const addAllLayers = async () => {
        await this.layerManager.addAllLayers(
          data.pointsGeoJSON,
          data.routesGeoJSON,
          data.visitsGeoJSON,
          data.photosGeoJSON,
          data.areasGeoJSON,
          data.tracksGeoJSON
        )

        // Setup event handlers
        this.layerManager.setupLayerEventHandlers({
          handlePointClick: this.eventHandlers.handlePointClick.bind(this.eventHandlers),
          handleVisitClick: this.eventHandlers.handleVisitClick.bind(this.eventHandlers),
          handlePhotoClick: this.eventHandlers.handlePhotoClick.bind(this.eventHandlers)
        })
      }

      // Use 'load' event which fires when map is fully initialized
      if (this.map.loaded()) {
        await addAllLayers()
      } else {
        this.map.once('load', async () => {
          await addAllLayers()
        })
      }

      // Fit map to data bounds
      if (data.points.length > 0) {
        this.fitMapToBounds(data.pointsGeoJSON)
      }

      // Show success toast
      Toast.success(`Loaded ${data.points.length} location ${data.points.length === 1 ? 'point' : 'points'}`)

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
    const { startDate, endDate } = DateManager.parseMonthSelector(event.target.value)
    this.startDateValue = startDate
    this.endDateValue = endDate

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

    const visible = this.layerManager.toggleLayer(layerName)
    if (visible === null) return

    // Update button style
    if (visible) {
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
    const pointsLayer = this.layerManager.getLayer('points')
    if (!pointsLayer) return

    const button = event.currentTarget

    // Toggle clustering state
    const newClusteringState = !pointsLayer.clusteringEnabled
    pointsLayer.toggleClustering(newClusteringState)

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

    // Clear layer references
    this.layerManager.clearLayerReferences()

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

    const heatmapLayer = this.layerManager.getLayer('heatmap')
    if (heatmapLayer) {
      if (enabled) {
        heatmapLayer.show()
      } else {
        heatmapLayer.hide()
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
   * Toggle visits layer
   */
  toggleVisits(event) {
    const enabled = event.target.checked
    SettingsManager.updateSetting('visitsEnabled', enabled)

    const visitsLayer = this.layerManager.getLayer('visits')
    if (visitsLayer) {
      if (enabled) {
        visitsLayer.show()
        // Show visits search
        if (this.hasVisitsSearchTarget) {
          this.visitsSearchTarget.style.display = 'block'
        }
      } else {
        visitsLayer.hide()
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

    const photosLayer = this.layerManager.getLayer('photos')
    if (photosLayer) {
      if (enabled) {
        photosLayer.show()
      } else {
        photosLayer.hide()
      }
    }
  }

  /**
   * Search visits
   */
  searchVisits(event) {
    const searchTerm = event.target.value.toLowerCase()
    const visitsLayer = this.layerManager.getLayer('visits')
    this.filterManager.filterAndUpdateVisits(
      searchTerm,
      this.filterManager.getCurrentVisitFilter(),
      visitsLayer
    )
  }

  /**
   * Filter visits by status
   */
  filterVisits(event) {
    const filter = event.target.value
    this.filterManager.setCurrentVisitFilter(filter)
    const searchTerm = document.getElementById('visits-search')?.value.toLowerCase() || ''
    const visitsLayer = this.layerManager.getLayer('visits')
    this.filterManager.filterAndUpdateVisits(searchTerm, filter, visitsLayer)
  }

  /**
   * Toggle areas layer
   */
  toggleAreas(event) {
    const enabled = event.target.checked
    SettingsManager.updateSetting('areasEnabled', enabled)

    const areasLayer = this.layerManager.getLayer('areas')
    if (areasLayer) {
      if (enabled) {
        areasLayer.show()
      } else {
        areasLayer.hide()
      }
    }
  }

  /**
   * Toggle tracks layer
   */
  toggleTracks(event) {
    const enabled = event.target.checked
    SettingsManager.updateSetting('tracksEnabled', enabled)

    const tracksLayer = this.layerManager.getLayer('tracks')
    if (tracksLayer) {
      if (enabled) {
        tracksLayer.show()
      } else {
        tracksLayer.hide()
      }
    }
  }

  /**
   * Toggle fog of war layer
   */
  toggleFog(event) {
    const enabled = event.target.checked
    SettingsManager.updateSetting('fogEnabled', enabled)

    const fogLayer = this.layerManager.getLayer('fog')
    if (fogLayer) {
      fogLayer.toggle(enabled)
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
      const scratchLayer = this.layerManager.getLayer('scratch')
      if (!scratchLayer && enabled) {
        // Lazy load scratch layer
        const ScratchLayer = await lazyLoader.loadLayer('scratch')
        const newScratchLayer = new ScratchLayer(this.map, {
          visible: true,
          apiClient: this.api
        })
        const pointsLayer = this.layerManager.getLayer('points')
        const pointsData = pointsLayer?.data || { type: 'FeatureCollection', features: [] }
        await newScratchLayer.add(pointsData)
        this.layerManager.layers.scratchLayer = newScratchLayer
      } else if (scratchLayer) {
        if (enabled) {
          scratchLayer.show()
        } else {
          scratchLayer.hide()
        }
      }
    } catch (error) {
      console.error('Failed to toggle scratch layer:', error)
      Toast.error('Failed to load scratch layer')
    }
  }
}
