import { Controller } from '@hotwired/stimulus'
import { ApiClient } from 'maps_maplibre/services/api_client'
import { SettingsManager } from 'maps_maplibre/utils/settings_manager'
import { SearchManager } from 'maps_maplibre/utils/search_manager'
import { Toast } from 'maps_maplibre/components/toast'
import { performanceMonitor } from 'maps_maplibre/utils/performance_monitor'
import { CleanupHelper } from 'maps_maplibre/utils/cleanup_helper'
import { MapInitializer } from './maplibre/map_initializer'
import { MapDataManager } from './maplibre/map_data_manager'
import { LayerManager } from './maplibre/layer_manager'
import { DataLoader } from './maplibre/data_loader'
import { EventHandlers } from './maplibre/event_handlers'
import { FilterManager } from './maplibre/filter_manager'
import { DateManager } from './maplibre/date_manager'
import { SettingsController } from './maplibre/settings_manager'
import { AreaSelectionManager } from './maplibre/area_selection_manager'
import { VisitsManager } from './maplibre/visits_manager'
import { PlacesManager } from './maplibre/places_manager'
import { RoutesManager } from './maplibre/routes_manager'

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

  static targets = [
    'container',
    'loading',
    'loadingText',
    'monthSelect',
    'clusterToggle',
    'settingsPanel',
    'visitsSearch',
    'routeOpacityRange',
    'placesFilters',
    'enableAllPlaceTagsToggle',
    'fogRadiusValue',
    'fogThresholdValue',
    'metersBetweenValue',
    'minutesBetweenValue',
    // Search
    'searchInput',
    'searchResults',
    // Layer toggles
    'pointsToggle',
    'routesToggle',
    'heatmapToggle',
    'visitsToggle',
    'photosToggle',
    'areasToggle',
    'placesToggle',
    'fogToggle',
    'scratchToggle',
    // Speed-colored routes
    'routesOptions',
    'speedColoredToggle',
    'speedColorScaleContainer',
    'speedColorScaleInput',
    // Area selection
    'selectAreaButton',
    'selectionActions',
    'deleteButtonText',
    'selectedVisitsContainer',
    'selectedVisitsBulkActions'
  ]

  async connect() {
    this.cleanup = new CleanupHelper()

    // Initialize API and settings
    SettingsManager.initialize(this.apiKeyValue)
    this.settingsController = new SettingsController(this)
    await this.settingsController.loadSettings()
    this.settings = this.settingsController.settings

    // Sync toggle states with loaded settings
    this.settingsController.syncToggleStates()

    await this.initializeMap()
    this.initializeAPI()

    // Initialize managers
    this.layerManager = new LayerManager(this.map, this.settings, this.api)
    this.dataLoader = new DataLoader(this.api, this.apiKeyValue)
    this.eventHandlers = new EventHandlers(this.map)
    this.filterManager = new FilterManager(this.dataLoader)
    this.mapDataManager = new MapDataManager(this)

    // Initialize feature managers
    this.areaSelectionManager = new AreaSelectionManager(this)
    this.visitsManager = new VisitsManager(this)
    this.placesManager = new PlacesManager(this)
    this.routesManager = new RoutesManager(this)

    // Initialize search manager
    this.initializeSearch()

    // Listen for visit and place creation events
    this.boundHandleVisitCreated = this.visitsManager.handleVisitCreated.bind(this.visitsManager)
    this.cleanup.addEventListener(document, 'visit:created', this.boundHandleVisitCreated)

    this.boundHandlePlaceCreated = this.placesManager.handlePlaceCreated.bind(this.placesManager)
    this.cleanup.addEventListener(document, 'place:created', this.boundHandlePlaceCreated)

    this.boundHandleAreaCreated = this.handleAreaCreated.bind(this)
    this.cleanup.addEventListener(document, 'area:created', this.boundHandleAreaCreated)

    // Format initial dates
    this.startDateValue = DateManager.formatDateForAPI(new Date(this.startDateValue))
    this.endDateValue = DateManager.formatDateForAPI(new Date(this.endDateValue))
    console.log('[Maps V2] Initial dates:', this.startDateValue, 'to', this.endDateValue)

    this.loadMapData()
  }

  disconnect() {
    this.searchManager?.destroy()
    this.cleanup.cleanup()
    this.map?.remove()
    performanceMonitor.logReport()
  }

  /**
   * Initialize MapLibre map
   */
  async initializeMap() {
    this.map = await MapInitializer.initialize(this.containerTarget, {
      mapStyle: this.settings.mapStyle
    })
  }

  /**
   * Initialize API client
   */
  initializeAPI() {
    this.api = new ApiClient(this.apiKeyValue)
  }

  /**
   * Initialize location search
   */
  initializeSearch() {
    if (!this.hasSearchInputTarget || !this.hasSearchResultsTarget) {
      console.warn('[Maps V2] Search targets not found, search functionality disabled')
      return
    }

    this.searchManager = new SearchManager(this.map, this.apiKeyValue)
    this.searchManager.initialize(this.searchInputTarget, this.searchResultsTarget)

    console.log('[Maps V2] Search manager initialized')
  }

  /**
   * Load map data from API
   */
  async loadMapData(options = {}) {
    return this.mapDataManager.loadMapData(
      this.startDateValue,
      this.endDateValue,
      {
        ...options,
        onProgress: this.updateLoadingProgress.bind(this)
      }
    )
  }

  /**
   * Month selector changed
   */
  monthChanged(event) {
    const { startDate, endDate } = DateManager.parseMonthSelector(event.target.value)
    this.startDateValue = startDate
    this.endDateValue = endDate

    console.log('[Maps V2] Date range changed:', this.startDateValue, 'to', this.endDateValue)
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
   * Toggle settings panel
   */
  toggleSettings() {
    if (this.hasSettingsPanelTarget) {
      this.settingsPanelTarget.classList.toggle('open')
    }
  }

  // ===== Delegated Methods to Managers =====

  // Settings Controller methods
  updateMapStyle(event) { return this.settingsController.updateMapStyle(event) }
  resetSettings() { return this.settingsController.resetSettings() }
  updateRouteOpacity(event) { return this.settingsController.updateRouteOpacity(event) }
  updateAdvancedSettings(event) { return this.settingsController.updateAdvancedSettings(event) }
  updateFogRadiusDisplay(event) { return this.settingsController.updateFogRadiusDisplay(event) }
  updateFogThresholdDisplay(event) { return this.settingsController.updateFogThresholdDisplay(event) }
  updateMetersBetweenDisplay(event) { return this.settingsController.updateMetersBetweenDisplay(event) }
  updateMinutesBetweenDisplay(event) { return this.settingsController.updateMinutesBetweenDisplay(event) }

  // Area Selection Manager methods
  startSelectArea() { return this.areaSelectionManager.startSelectArea() }
  cancelAreaSelection() { return this.areaSelectionManager.cancelAreaSelection() }
  deleteSelectedPoints() { return this.areaSelectionManager.deleteSelectedPoints() }

  // Visits Manager methods
  toggleVisits(event) { return this.visitsManager.toggleVisits(event) }
  searchVisits(event) { return this.visitsManager.searchVisits(event) }
  filterVisits(event) { return this.visitsManager.filterVisits(event) }
  startCreateVisit() { return this.visitsManager.startCreateVisit() }

  // Places Manager methods
  togglePlaces(event) { return this.placesManager.togglePlaces(event) }
  filterPlacesByTags(event) { return this.placesManager.filterPlacesByTags(event) }
  toggleAllPlaceTags(event) { return this.placesManager.toggleAllPlaceTags(event) }
  startCreatePlace() { return this.placesManager.startCreatePlace() }

  // Area creation
  startCreateArea() {
    console.log('[Maps V2] Starting create area mode')

    if (this.hasSettingsPanelTarget && this.settingsPanelTarget.classList.contains('open')) {
      this.toggleSettings()
    }

    // Find area drawer controller on the same element
    const drawerController = this.application.getControllerForElementAndIdentifier(
      this.element,
      'area-drawer'
    )

    if (drawerController) {
      console.log('[Maps V2] Area drawer controller found, starting drawing with map:', this.map)
      drawerController.startDrawing(this.map)
    } else {
      console.error('[Maps V2] Area drawer controller not found')
      Toast.error('Area drawer controller not available')
    }
  }

  async handleAreaCreated(event) {
    console.log('[Maps V2] Area created:', event.detail.area)

    try {
      // Fetch all areas from API
      const areas = await this.api.fetchAreas()
      console.log('[Maps V2] Fetched areas:', areas.length)

      // Convert to GeoJSON
      const areasGeoJSON = this.dataLoader.areasToGeoJSON(areas)
      console.log('[Maps V2] Converted to GeoJSON:', areasGeoJSON.features.length, 'features')
      if (areasGeoJSON.features.length > 0) {
        console.log('[Maps V2] First area GeoJSON:', JSON.stringify(areasGeoJSON.features[0], null, 2))
      }

      // Get or create the areas layer
      let areasLayer = this.layerManager.getLayer('areas')
      console.log('[Maps V2] Areas layer exists?', !!areasLayer, 'visible?', areasLayer?.visible)

      if (areasLayer) {
        // Update existing layer
        areasLayer.update(areasGeoJSON)
        console.log('[Maps V2] Areas layer updated')
      } else {
        // Create the layer if it doesn't exist yet
        console.log('[Maps V2] Creating areas layer')
        this.layerManager._addAreasLayer(areasGeoJSON)
        areasLayer = this.layerManager.getLayer('areas')
        console.log('[Maps V2] Areas layer created, visible?', areasLayer?.visible)
      }

      // Enable the layer if it wasn't already
      if (areasLayer) {
        if (!areasLayer.visible) {
          console.log('[Maps V2] Showing areas layer')
          areasLayer.show()
          this.settings.layers.areas = true
          this.settingsController.saveSetting('layers.areas', true)

          // Update toggle state
          if (this.hasAreasToggleTarget) {
            this.areasToggleTarget.checked = true
          }
        } else {
          console.log('[Maps V2] Areas layer already visible')
        }
      }

      Toast.success('Area created successfully!')
    } catch (error) {
      console.error('[Maps V2] Failed to reload areas:', error)
      Toast.error('Failed to reload areas')
    }
  }

  // Routes Manager methods
  togglePoints(event) { return this.routesManager.togglePoints(event) }
  toggleRoutes(event) { return this.routesManager.toggleRoutes(event) }
  toggleHeatmap(event) { return this.routesManager.toggleHeatmap(event) }
  toggleFog(event) { return this.routesManager.toggleFog(event) }
  toggleScratch(event) { return this.routesManager.toggleScratch(event) }
  togglePhotos(event) { return this.routesManager.togglePhotos(event) }
  toggleAreas(event) { return this.routesManager.toggleAreas(event) }
  toggleTracks(event) { return this.routesManager.toggleTracks(event) }
  toggleSpeedColoredRoutes(event) { return this.routesManager.toggleSpeedColoredRoutes(event) }
  openSpeedColorEditor() { return this.routesManager.openSpeedColorEditor() }
  handleSpeedColorSave(event) { return this.routesManager.handleSpeedColorSave(event) }
}
