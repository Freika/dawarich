import { Controller } from '@hotwired/stimulus'
import maplibregl from 'maplibre-gl'
import { ApiClient } from 'maps_v2/services/api_client'
import { SettingsManager } from 'maps_v2/utils/settings_manager'
import { SearchManager } from 'maps_v2/utils/search_manager'
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
import { SelectionLayer } from 'maps_v2/layers/selection_layer'
import { SelectedPointsLayer } from 'maps_v2/layers/selected_points_layer'
import { pointsToGeoJSON } from 'maps_v2/utils/geojson_transformers'
import { VisitCard } from 'maps_v2/components/visit_card'

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
    // 'tracksToggle',
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

    // Initialize settings manager with API key for backend sync
    SettingsManager.initialize(this.apiKeyValue)

    // Sync settings from backend (will fall back to localStorage if needed)
    await this.loadSettings()

    // Sync toggle states with loaded settings
    this.syncToggleStates()

    await this.initializeMap()
    this.initializeAPI()

    // Initialize managers
    this.layerManager = new LayerManager(this.map, this.settings, this.api)
    this.dataLoader = new DataLoader(this.api, this.apiKeyValue)
    this.eventHandlers = new EventHandlers(this.map)
    this.filterManager = new FilterManager(this.dataLoader)

    // Initialize search manager
    this.initializeSearch()

    // Listen for visit creation events
    this.boundHandleVisitCreated = this.handleVisitCreated.bind(this)
    this.cleanup.addEventListener(document, 'visit:created', this.boundHandleVisitCreated)

    // Listen for place creation events
    this.boundHandlePlaceCreated = this.handlePlaceCreated.bind(this)
    this.cleanup.addEventListener(document, 'place:created', this.boundHandlePlaceCreated)

    // Format initial dates from backend to match V1 API format
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
   * Load settings (sync from backend and localStorage)
   */
  async loadSettings() {
    this.settings = await SettingsManager.sync()
    console.log('[Maps V2] Settings loaded:', this.settings)
  }

  /**
   * Sync UI controls with loaded settings
   */
  syncToggleStates() {
    // Sync layer toggles
    const toggleMap = {
      pointsToggle: 'pointsVisible',
      routesToggle: 'routesVisible',
      heatmapToggle: 'heatmapEnabled',
      visitsToggle: 'visitsEnabled',
      photosToggle: 'photosEnabled',
      areasToggle: 'areasEnabled',
      placesToggle: 'placesEnabled',
      // tracksToggle: 'tracksEnabled',
      fogToggle: 'fogEnabled',
      scratchToggle: 'scratchEnabled',
      speedColoredToggle: 'speedColoredRoutesEnabled'
    }

    Object.entries(toggleMap).forEach(([targetName, settingKey]) => {
      const target = `${targetName}Target`
      if (this[target]) {
        this[target].checked = this.settings[settingKey]
      }
    })

    // Show/hide visits search based on initial toggle state
    if (this.hasVisitsToggleTarget && this.hasVisitsSearchTarget) {
      if (this.visitsToggleTarget.checked) {
        this.visitsSearchTarget.style.display = 'block'
      } else {
        this.visitsSearchTarget.style.display = 'none'
      }
    }

    // Show/hide places filters based on initial toggle state
    if (this.hasPlacesToggleTarget && this.hasPlacesFiltersTarget) {
      if (this.placesToggleTarget.checked) {
        this.placesFiltersTarget.style.display = 'block'
      } else {
        this.placesFiltersTarget.style.display = 'none'
      }
    }

    // Sync route opacity slider
    if (this.hasRouteOpacityRangeTarget) {
      this.routeOpacityRangeTarget.value = (this.settings.routeOpacity || 1.0) * 100
    }

    // Sync map style dropdown
    const mapStyleSelect = this.element.querySelector('select[name="mapStyle"]')
    if (mapStyleSelect) {
      mapStyleSelect.value = this.settings.mapStyle || 'light'
    }

    // Sync fog of war settings
    const fogRadiusInput = this.element.querySelector('input[name="fogOfWarRadius"]')
    if (fogRadiusInput) {
      fogRadiusInput.value = this.settings.fogOfWarRadius || 1000
      if (this.hasFogRadiusValueTarget) {
        this.fogRadiusValueTarget.textContent = `${fogRadiusInput.value}m`
      }
    }

    const fogThresholdInput = this.element.querySelector('input[name="fogOfWarThreshold"]')
    if (fogThresholdInput) {
      fogThresholdInput.value = this.settings.fogOfWarThreshold || 1
      if (this.hasFogThresholdValueTarget) {
        this.fogThresholdValueTarget.textContent = fogThresholdInput.value
      }
    }

    // Sync route generation settings
    const metersBetweenInput = this.element.querySelector('input[name="metersBetweenRoutes"]')
    if (metersBetweenInput) {
      metersBetweenInput.value = this.settings.metersBetweenRoutes || 500
      if (this.hasMetersBetweenValueTarget) {
        this.metersBetweenValueTarget.textContent = `${metersBetweenInput.value}m`
      }
    }

    const minutesBetweenInput = this.element.querySelector('input[name="minutesBetweenRoutes"]')
    if (minutesBetweenInput) {
      minutesBetweenInput.value = this.settings.minutesBetweenRoutes || 60
      if (this.hasMinutesBetweenValueTarget) {
        this.minutesBetweenValueTarget.textContent = `${minutesBetweenInput.value}min`
      }
    }

    // Sync speed-colored routes settings
    if (this.hasSpeedColorScaleInputTarget) {
      const colorScale = this.settings.speedColorScale || '0:#00ff00|15:#00ffff|30:#ff00ff|50:#ffff00|100:#ff3300'
      this.speedColorScaleInputTarget.value = colorScale
    }
    if (this.hasSpeedColorScaleContainerTarget && this.hasSpeedColoredToggleTarget) {
      const isEnabled = this.speedColoredToggleTarget.checked
      this.speedColorScaleContainerTarget.classList.toggle('hidden', !isEnabled)
    }

    // Sync points rendering mode radio buttons
    const pointsRenderingRadios = this.element.querySelectorAll('input[name="pointsRenderingMode"]')
    pointsRenderingRadios.forEach(radio => {
      radio.checked = radio.value === (this.settings.pointsRenderingMode || 'raw')
    })

    // Sync speed-colored routes toggle
    const speedColoredRoutesToggle = this.element.querySelector('input[name="speedColoredRoutes"]')
    if (speedColoredRoutesToggle) {
      speedColoredRoutesToggle.checked = this.settings.speedColoredRoutes || false
    }

    console.log('[Maps V2] UI controls synced with settings')
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
   * Handle visit creation event - reload visits and update layer
   */
  async handleVisitCreated(event) {
    console.log('[Maps V2] Visit created, reloading visits...', event.detail)

    try {
      // Fetch updated visits
      const visits = await this.api.fetchVisits({
        start_at: this.startDateValue,
        end_at: this.endDateValue
      })

      console.log('[Maps V2] Fetched visits:', visits.length)

      // Update FilterManager with all visits (for search functionality)
      this.filterManager.setAllVisits(visits)

      // Convert to GeoJSON
      const visitsGeoJSON = this.dataLoader.visitsToGeoJSON(visits)

      console.log('[Maps V2] Converted to GeoJSON:', visitsGeoJSON.features.length, 'features')

      // Get the visits layer and update it
      const visitsLayer = this.layerManager.getLayer('visits')
      if (visitsLayer) {
        visitsLayer.update(visitsGeoJSON)
        console.log('[Maps V2] Visits layer updated successfully')
      } else {
        console.warn('[Maps V2] Visits layer not found, cannot update')
      }
    } catch (error) {
      console.error('[Maps V2] Failed to reload visits:', error)
    }
  }

  /**
   * Handle place creation event - reload places and update layer
   */
  async handlePlaceCreated(event) {
    console.log('[Maps V2] Place created, reloading places...', event.detail)

    try {
      // Get currently selected tag filters
      const selectedTags = this.getSelectedPlaceTags()

      // Fetch updated places with filters
      const places = await this.api.fetchPlaces({
        tag_ids: selectedTags
      })

      console.log('[Maps V2] Fetched places:', places.length)

      // Convert to GeoJSON
      const placesGeoJSON = this.dataLoader.placesToGeoJSON(places)

      console.log('[Maps V2] Converted to GeoJSON:', placesGeoJSON.features.length, 'features')

      // Get the places layer and update it
      const placesLayer = this.layerManager.getLayer('places')
      if (placesLayer) {
        placesLayer.update(placesGeoJSON)
        console.log('[Maps V2] Places layer updated successfully')
      } else {
        console.warn('[Maps V2] Places layer not found, cannot update')
      }
    } catch (error) {
      console.error('[Maps V2] Failed to reload places:', error)
    }
  }

  /**
   * Start create visit mode
   * Allows user to click on map to create a new visit
   */
  startCreateVisit() {
    console.log('[Maps V2] Starting create visit mode')

    // Close settings panel
    if (this.hasSettingsPanelTarget && this.settingsPanelTarget.classList.contains('open')) {
      this.toggleSettings()
    }

    // Change cursor to crosshair
    this.map.getCanvas().style.cursor = 'crosshair'

    // Show info message
    Toast.info('Click on the map to place a visit')

    // Add map click listener
    this.handleCreateVisitClick = (e) => {
      const { lng, lat } = e.lngLat
      this.openVisitCreationModal(lat, lng)
      // Reset cursor
      this.map.getCanvas().style.cursor = ''
    }

    this.map.once('click', this.handleCreateVisitClick)
  }

  /**
   * Open visit creation modal
   */
  openVisitCreationModal(lat, lng) {
    console.log('[Maps V2] Opening visit creation modal', { lat, lng })

    // Find the visit creation controller
    const modalElement = document.querySelector('[data-controller="visit-creation-v2"]')

    if (!modalElement) {
      console.error('[Maps V2] Visit creation modal not found')
      Toast.error('Visit creation modal not available')
      return
    }

    // Get the controller instance
    const controller = this.application.getControllerForElementAndIdentifier(
      modalElement,
      'visit-creation-v2'
    )

    if (controller) {
      controller.open(lat, lng, this)
    } else {
      console.error('[Maps V2] Visit creation controller not found')
      Toast.error('Visit creation controller not available')
    }
  }

  /**
   * Start create place mode
   * Allows user to click on map to create a new place
   */
  startCreatePlace() {
    console.log('[Maps V2] Starting create place mode')

    // Close settings panel
    if (this.hasSettingsPanelTarget && this.settingsPanelTarget.classList.contains('open')) {
      this.toggleSettings()
    }

    // Change cursor to crosshair
    this.map.getCanvas().style.cursor = 'crosshair'

    // Show info message
    Toast.info('Click on the map to place a place')

    // Add map click listener
    this.handleCreatePlaceClick = (e) => {
      const { lng, lat } = e.lngLat

      // Dispatch event for place creation modal (reuse existing controller)
      document.dispatchEvent(new CustomEvent('place:create', {
        detail: { latitude: lat, longitude: lng }
      }))

      // Reset cursor
      this.map.getCanvas().style.cursor = ''
    }

    this.map.once('click', this.handleCreatePlaceClick)
  }

  /**
   * Load map data from API
   * @param {Object} options - { showLoading, fitBounds, showToast }
   */
  async loadMapData(options = {}) {
    const {
      showLoading = true,
      fitBounds = true,
      showToast = true
    } = options

    performanceMonitor.mark('load-map-data')

    if (showLoading) {
      this.showLoading()
    }

    try {
      // Fetch all map data
      const data = await this.dataLoader.fetchMapData(
        this.startDateValue,
        this.endDateValue,
        showLoading ? this.updateLoadingProgress.bind(this) : null
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
          data.tracksGeoJSON,
          data.placesGeoJSON
        )

        // Setup event handlers
        this.layerManager.setupLayerEventHandlers({
          handlePointClick: this.eventHandlers.handlePointClick.bind(this.eventHandlers),
          handleVisitClick: this.eventHandlers.handleVisitClick.bind(this.eventHandlers),
          handlePhotoClick: this.eventHandlers.handlePhotoClick.bind(this.eventHandlers),
          handlePlaceClick: this.eventHandlers.handlePlaceClick.bind(this.eventHandlers)
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

      // Fit map to data bounds (optional)
      if (fitBounds && data.points.length > 0) {
        this.fitMapToBounds(data.pointsGeoJSON)
      }

      // Show success toast (optional)
      if (showToast) {
        Toast.success(`Loaded ${data.points.length} location ${data.points.length === 1 ? 'point' : 'points'}`)
      }

    } catch (error) {
      console.error('Failed to load map data:', error)
      Toast.error('Failed to load location data. Please try again.')
    } finally {
      if (showLoading) {
        this.hideLoading()
      }
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
    const element = event.currentTarget
    const layerName = element.dataset.layer || event.params?.layer

    const visible = this.layerManager.toggleLayer(layerName)
    if (visible === null) return

    // Update button style (for button-based toggles)
    if (element.tagName === 'BUTTON') {
      if (visible) {
        element.classList.add('btn-primary')
        element.classList.remove('btn-outline')
      } else {
        element.classList.remove('btn-primary')
        element.classList.add('btn-outline')
      }
    }

    // Update checkbox state (for checkbox-based toggles)
    if (element.tagName === 'INPUT' && element.type === 'checkbox') {
      element.checked = visible
    }
  }

  /**
   * Toggle points layer visibility
   */
  togglePoints(event) {
    const element = event.currentTarget
    const visible = element.checked

    const pointsLayer = this.layerManager.getLayer('points')
    if (pointsLayer) {
      pointsLayer.toggle(visible)
    }

    // Save setting
    SettingsManager.updateSetting('pointsVisible', visible)
  }

  /**
   * Toggle routes layer visibility
   */
  toggleRoutes(event) {
    const element = event.currentTarget
    const visible = element.checked

    const routesLayer = this.layerManager.getLayer('routes')
    if (routesLayer) {
      routesLayer.toggle(visible)
    }

    // Show/hide routes options panel
    if (this.hasRoutesOptionsTarget) {
      this.routesOptionsTarget.style.display = visible ? 'block' : 'none'
    }

    // Save setting
    SettingsManager.updateSetting('routesVisible', visible)
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
   * Update route opacity in real-time
   */
  updateRouteOpacity(event) {
    const opacity = parseInt(event.target.value) / 100

    const routesLayer = this.layerManager.getLayer('routes')
    if (routesLayer && this.map.getLayer('routes')) {
      this.map.setPaintProperty('routes', 'line-opacity', opacity)
    }

    // Save setting
    SettingsManager.updateSetting('routeOpacity', opacity)
  }

  /**
   * Update fog radius display value
   */
  updateFogRadiusDisplay(event) {
    if (this.hasFogRadiusValueTarget) {
      this.fogRadiusValueTarget.textContent = `${event.target.value}m`
    }
  }

  /**
   * Update fog threshold display value
   */
  updateFogThresholdDisplay(event) {
    if (this.hasFogThresholdValueTarget) {
      this.fogThresholdValueTarget.textContent = event.target.value
    }
  }

  /**
   * Update meters between routes display value
   */
  updateMetersBetweenDisplay(event) {
    if (this.hasMetersBetweenValueTarget) {
      this.metersBetweenValueTarget.textContent = `${event.target.value}m`
    }
  }

  /**
   * Update minutes between routes display value
   */
  updateMinutesBetweenDisplay(event) {
    if (this.hasMinutesBetweenValueTarget) {
      this.minutesBetweenValueTarget.textContent = `${event.target.value}min`
    }
  }

  /**
   * Update advanced settings from form submission
   */
  async updateAdvancedSettings(event) {
    event.preventDefault()

    const formData = new FormData(event.target)
    const settings = {
      routeOpacity: parseFloat(formData.get('routeOpacity')) / 100,
      fogOfWarRadius: parseInt(formData.get('fogOfWarRadius')),
      fogOfWarThreshold: parseInt(formData.get('fogOfWarThreshold')),
      metersBetweenRoutes: parseInt(formData.get('metersBetweenRoutes')),
      minutesBetweenRoutes: parseInt(formData.get('minutesBetweenRoutes')),
      pointsRenderingMode: formData.get('pointsRenderingMode'),
      speedColoredRoutes: formData.get('speedColoredRoutes') === 'on'
    }

    // Apply settings to current map
    await this.applySettingsToMap(settings)

    // Save to backend and localStorage
    for (const [key, value] of Object.entries(settings)) {
      await SettingsManager.updateSetting(key, value)
    }

    Toast.success('Settings updated successfully')
  }

  /**
   * Apply settings to map without reload
   */
  async applySettingsToMap(settings) {
    // Update route opacity
    if (settings.routeOpacity !== undefined) {
      const routesLayer = this.layerManager.getLayer('routes')
      if (routesLayer && this.map.getLayer('routes')) {
        this.map.setPaintProperty('routes', 'line-opacity', settings.routeOpacity)
      }
    }

    // Update fog of war settings
    if (settings.fogOfWarRadius !== undefined || settings.fogOfWarThreshold !== undefined) {
      const fogLayer = this.layerManager.getLayer('fog')
      if (fogLayer) {
        if (settings.fogOfWarRadius) {
          fogLayer.clearRadius = settings.fogOfWarRadius
        }
        // Redraw fog layer
        if (fogLayer.visible) {
          await fogLayer.update(fogLayer.data)
        }
      }
    }

    // For settings that require data reload (points rendering mode, speed-colored routes, etc)
    // we need to reload the map data
    if (settings.pointsRenderingMode || settings.speedColoredRoutes !== undefined) {
      Toast.info('Reloading map data with new settings...')
      await this.loadMapData()
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
   * Toggle places layer
   */
  togglePlaces(event) {
    const enabled = event.target.checked
    SettingsManager.updateSetting('placesEnabled', enabled)

    const placesLayer = this.layerManager.getLayer('places')
    if (placesLayer) {
      if (enabled) {
        placesLayer.show()
        // Show places filters
        if (this.hasPlacesFiltersTarget) {
          this.placesFiltersTarget.style.display = 'block'
        }

        // Initialize tag filters: enable all tags if no saved selection exists
        this.initializePlaceTagFilters()
      } else {
        placesLayer.hide()
        // Hide places filters
        if (this.hasPlacesFiltersTarget) {
          this.placesFiltersTarget.style.display = 'none'
        }
      }
    }
  }

  /**
   * Initialize place tag filters (enable all by default or restore saved state)
   */
  initializePlaceTagFilters() {
    const savedFilters = this.settings.placesTagFilters

    if (savedFilters && savedFilters.length > 0) {
      // Restore saved tag selection
      this.restoreSavedTagFilters(savedFilters)
    } else {
      // Default: enable all tags
      this.enableAllTagsInitial()
    }
  }

  /**
   * Restore saved tag filters
   */
  restoreSavedTagFilters(savedFilters) {
    const tagCheckboxes = document.querySelectorAll('input[name="place_tag_ids[]"]')

    tagCheckboxes.forEach(checkbox => {
      const value = checkbox.value === 'untagged' ? checkbox.value : parseInt(checkbox.value)
      const shouldBeChecked = savedFilters.includes(value)

      if (checkbox.checked !== shouldBeChecked) {
        checkbox.checked = shouldBeChecked

        // Update badge styling
        const badge = checkbox.nextElementSibling
        const color = badge.style.borderColor

        if (shouldBeChecked) {
          badge.classList.remove('badge-outline')
          badge.style.backgroundColor = color
          badge.style.color = 'white'
        } else {
          badge.classList.add('badge-outline')
          badge.style.backgroundColor = 'transparent'
          badge.style.color = color
        }
      }
    })

    // Sync "Enable All Tags" toggle
    this.syncEnableAllTagsToggle()

    // Load places with restored filters
    this.loadPlacesWithTags(savedFilters)
  }

  /**
   * Enable all tags initially
   */
  enableAllTagsInitial() {
    if (this.hasEnableAllPlaceTagsToggleTarget) {
      this.enableAllPlaceTagsToggleTarget.checked = true
    }

    const tagCheckboxes = document.querySelectorAll('input[name="place_tag_ids[]"]')
    const allTagIds = []

    tagCheckboxes.forEach(checkbox => {
      checkbox.checked = true

      // Update badge styling
      const badge = checkbox.nextElementSibling
      const color = badge.style.borderColor
      badge.classList.remove('badge-outline')
      badge.style.backgroundColor = color
      badge.style.color = 'white'

      // Collect tag IDs
      const value = checkbox.value === 'untagged' ? checkbox.value : parseInt(checkbox.value)
      allTagIds.push(value)
    })

    // Save to settings
    SettingsManager.updateSetting('placesTagFilters', allTagIds)

    // Load places with all tags
    this.loadPlacesWithTags(allTagIds)
  }

  /**
   * Get selected place tag IDs
   */
  getSelectedPlaceTags() {
    return Array.from(
      document.querySelectorAll('input[name="place_tag_ids[]"]:checked')
    ).map(cb => {
      const value = cb.value
      // Keep "untagged" as string, convert others to integers
      return value === 'untagged' ? value : parseInt(value)
    })
  }

  /**
   * Filter places by selected tags
   */
  filterPlacesByTags(event) {
    // Update badge styles
    const badge = event.target.nextElementSibling
    const color = badge.style.borderColor

    if (event.target.checked) {
      badge.classList.remove('badge-outline')
      badge.style.backgroundColor = color
      badge.style.color = 'white'
    } else {
      badge.classList.add('badge-outline')
      badge.style.backgroundColor = 'transparent'
      badge.style.color = color
    }

    // Sync "Enable All Tags" toggle state
    this.syncEnableAllTagsToggle()

    // Get all checked tag checkboxes
    const checkedTags = this.getSelectedPlaceTags()

    // Save selection to settings
    SettingsManager.updateSetting('placesTagFilters', checkedTags)

    // Reload places with selected tags (empty array = show NO places)
    this.loadPlacesWithTags(checkedTags)
  }

  /**
   * Sync "Enable All Tags" toggle with individual tag states
   */
  syncEnableAllTagsToggle() {
    if (!this.hasEnableAllPlaceTagsToggleTarget) return

    const tagCheckboxes = document.querySelectorAll('input[name="place_tag_ids[]"]')
    const allChecked = Array.from(tagCheckboxes).every(cb => cb.checked)
    const noneChecked = Array.from(tagCheckboxes).every(cb => !cb.checked)

    // Update toggle state without triggering change event
    this.enableAllPlaceTagsToggleTarget.checked = allChecked
  }

  /**
   * Load places filtered by tags
   */
  async loadPlacesWithTags(tagIds = []) {
    try {
      let places = []

      if (tagIds.length > 0) {
        // Fetch places with selected tags
        places = await this.api.fetchPlaces({ tag_ids: tagIds })
      }
      // If tagIds is empty, places remains empty array = show NO places

      const placesGeoJSON = this.dataLoader.placesToGeoJSON(places)

      const placesLayer = this.layerManager.getLayer('places')
      if (placesLayer) {
        placesLayer.update(placesGeoJSON)
      }
    } catch (error) {
      console.error('[Maps V2] Failed to load places:', error)
    }
  }

  /**
   * Toggle all place tags on/off
   */
  toggleAllPlaceTags(event) {
    const enableAll = event.target.checked
    const tagCheckboxes = document.querySelectorAll('input[name="place_tag_ids[]"]')

    tagCheckboxes.forEach(checkbox => {
      if (checkbox.checked !== enableAll) {
        checkbox.checked = enableAll

        // Update badge styling
        const badge = checkbox.nextElementSibling
        const color = badge.style.borderColor

        if (enableAll) {
          badge.classList.remove('badge-outline')
          badge.style.backgroundColor = color
          badge.style.color = 'white'
        } else {
          badge.classList.add('badge-outline')
          badge.style.backgroundColor = 'transparent'
          badge.style.color = color
        }
      }
    })

    // Get selected tags
    const selectedTags = this.getSelectedPlaceTags()

    // Save selection to settings
    SettingsManager.updateSetting('placesTagFilters', selectedTags)

    // Reload places with selected tags
    this.loadPlacesWithTags(selectedTags)
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

  /**
   * Toggle speed-colored routes
   */
  async toggleSpeedColoredRoutes(event) {
    const enabled = event.target.checked
    SettingsManager.updateSetting('speedColoredRoutesEnabled', enabled)

    // Show/hide color scale container
    if (this.hasSpeedColorScaleContainerTarget) {
      this.speedColorScaleContainerTarget.classList.toggle('hidden', !enabled)
    }

    // Reload routes with speed colors
    await this.reloadRoutes()
  }

  /**
   * Open speed color editor modal
   */
  openSpeedColorEditor() {
    const currentScale = this.speedColorScaleInputTarget.value || '0:#00ff00|15:#00ffff|30:#ff00ff|50:#ffff00|100:#ff3300'

    // Create modal if it doesn't exist
    let modal = document.getElementById('speed-color-editor-modal')
    if (!modal) {
      modal = this.createSpeedColorEditorModal(currentScale)
      document.body.appendChild(modal)
    } else {
      // Update existing modal with current scale
      const controller = this.application.getControllerForElementAndIdentifier(modal, 'speed-color-editor')
      if (controller) {
        controller.colorStopsValue = currentScale
        controller.loadColorStops()
      }
    }

    // Show modal
    const checkbox = modal.querySelector('.modal-toggle')
    if (checkbox) {
      checkbox.checked = true
    }
  }

  /**
   * Create speed color editor modal element
   */
  createSpeedColorEditorModal(currentScale) {
    const modal = document.createElement('div')
    modal.id = 'speed-color-editor-modal'
    modal.setAttribute('data-controller', 'speed-color-editor')
    modal.setAttribute('data-speed-color-editor-color-stops-value', currentScale)
    modal.setAttribute('data-action', 'speed-color-editor:save->maps-v2#handleSpeedColorSave')

    modal.innerHTML = `
      <input type="checkbox" id="speed-color-editor-toggle" class="modal-toggle" />
      <div class="modal" role="dialog" data-speed-color-editor-target="modal">
        <div class="modal-box max-w-2xl">
          <h3 class="text-lg font-bold mb-4">Edit Speed Color Gradient</h3>

          <div class="space-y-4">
            <!-- Gradient Preview -->
            <div class="form-control">
              <label class="label">
                <span class="label-text font-medium">Preview</span>
              </label>
              <div class="h-12 rounded-lg border-2 border-base-300"
                   data-speed-color-editor-target="preview"></div>
              <label class="label">
                <span class="label-text-alt">This gradient will be applied to routes based on speed</span>
              </label>
            </div>

            <!-- Color Stops List -->
            <div class="form-control">
              <label class="label">
                <span class="label-text font-medium">Color Stops</span>
              </label>
              <div class="space-y-2" data-speed-color-editor-target="stopsList"></div>
            </div>

            <!-- Add Stop Button -->
            <button type="button"
                    class="btn btn-sm btn-outline w-full"
                    data-action="click->speed-color-editor#addStop">
              <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4 mr-2" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
              </svg>
              Add Color Stop
            </button>
          </div>

          <div class="modal-action">
            <button type="button"
                    class="btn btn-ghost"
                    data-action="click->speed-color-editor#resetToDefault">
              Reset to Default
            </button>
            <button type="button"
                    class="btn"
                    data-action="click->speed-color-editor#close">
              Cancel
            </button>
            <button type="button"
                    class="btn btn-primary"
                    data-action="click->speed-color-editor#save">
              Save
            </button>
          </div>
        </div>
        <label class="modal-backdrop" for="speed-color-editor-toggle"></label>
      </div>
    `

    return modal
  }

  /**
   * Handle speed color save event from editor
   */
  handleSpeedColorSave(event) {
    const newScale = event.detail.colorStops

    // Save to settings
    this.speedColorScaleInputTarget.value = newScale
    SettingsManager.updateSetting('speedColorScale', newScale)

    // Reload routes if speed colors are enabled
    if (this.speedColoredToggleTarget.checked) {
      this.reloadRoutes()
    }
  }

  /**
   * Reload routes layer
   */
  async reloadRoutes() {
    this.showLoading('Reloading routes...')

    try {
      const pointsLayer = this.layerManager.getLayer('points')
      const points = pointsLayer?.data?.features?.map(f => ({
        latitude: f.geometry.coordinates[1],
        longitude: f.geometry.coordinates[0],
        timestamp: f.properties.timestamp
      })) || []

      // Get route generation settings
      const distanceThresholdMeters = this.settings.metersBetweenRoutes || 500
      const timeThresholdMinutes = this.settings.minutesBetweenRoutes || 60

      // Import speed colors utility
      const { calculateSpeed, getSpeedColor } = await import('maps_v2/utils/speed_colors')

      // Generate routes with speed coloring if enabled
      const routesGeoJSON = await this.generateRoutesWithSpeedColors(
        points,
        { distanceThresholdMeters, timeThresholdMinutes },
        calculateSpeed,
        getSpeedColor
      )

      // Update routes layer
      this.layerManager.updateLayer('routes', routesGeoJSON)

    } catch (error) {
      console.error('Failed to reload routes:', error)
      Toast.error('Failed to reload routes')
    } finally {
      this.hideLoading()
    }
  }

  /**
   * Generate routes with speed coloring
   */
  async generateRoutesWithSpeedColors(points, options, calculateSpeed, getSpeedColor) {
    const { RoutesLayer } = await import('maps_v2/layers/routes_layer')
    const useSpeedColors = this.settings.speedColoredRoutesEnabled || false
    const speedColorScale = this.settings.speedColorScale || '0:#00ff00|15:#00ffff|30:#ff00ff|50:#ffff00|100:#ff3300'

    // Use RoutesLayer static method to generate basic routes
    const routesGeoJSON = RoutesLayer.pointsToRoutes(points, options)

    if (!useSpeedColors) {
      return routesGeoJSON
    }

    // Add speed colors to route segments
    routesGeoJSON.features = routesGeoJSON.features.map((feature, index) => {
      const segment = points.slice(
        points.findIndex(p => p.timestamp === feature.properties.startTime),
        points.findIndex(p => p.timestamp === feature.properties.endTime) + 1
      )

      if (segment.length >= 2) {
        const speed = calculateSpeed(segment[0], segment[segment.length - 1])
        const color = getSpeedColor(speed, useSpeedColors, speedColorScale)
        feature.properties.speed = speed
        feature.properties.color = color
      }

      return feature
    })

    return routesGeoJSON
  }

  /**
   * Start area selection mode
   */
  async startSelectArea() {
    console.log('[Maps V2] Starting area selection mode')

    // Keep settings panel open during selection mode
    // (Don't close it)

    // Initialize selection layer if not exists
    if (!this.selectionLayer) {
      this.selectionLayer = new SelectionLayer(this.map, {
        visible: true,
        onSelectionComplete: this.handleAreaSelected.bind(this)
      })

      // Add layer to map immediately (map is already loaded at this point)
      this.selectionLayer.add({
        type: 'FeatureCollection',
        features: []
      })

      console.log('[Maps V2] Selection layer initialized')
    }

    // Initialize selected points layer if not exists
    if (!this.selectedPointsLayer) {
      this.selectedPointsLayer = new SelectedPointsLayer(this.map, {
        visible: true
      })

      // Add layer to map immediately (map is already loaded at this point)
      this.selectedPointsLayer.add({
        type: 'FeatureCollection',
        features: []
      })

      console.log('[Maps V2] Selected points layer initialized')
    }

    // Enable selection mode
    this.selectionLayer.enableSelectionMode()

    // Update UI - replace Select Area button with Cancel Selection button
    if (this.hasSelectAreaButtonTarget) {
      this.selectAreaButtonTarget.innerHTML = `
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="w-5 h-5">
          <line x1="18" y1="6" x2="6" y2="18"></line>
          <line x1="6" y1="6" x2="18" y2="18"></line>
        </svg>
        Cancel Selection
      `
      // Change action to cancel
      this.selectAreaButtonTarget.dataset.action = 'click->maps-v2#cancelAreaSelection'
    }

    Toast.info('Draw a rectangle on the map to select points')
  }

  /**
   * Handle area selection completion
   */
  async handleAreaSelected(bounds) {
    console.log('[Maps V2] Area selected:', bounds)

    try {
      // Fetch both points and visits within the selected area
      Toast.info('Fetching data in selected area...')

      const [points, visits] = await Promise.all([
        this.api.fetchPointsInArea({
          start_at: this.startDateValue,
          end_at: this.endDateValue,
          min_longitude: bounds.minLng,
          max_longitude: bounds.maxLng,
          min_latitude: bounds.minLat,
          max_latitude: bounds.maxLat
        }),
        this.api.fetchVisitsInArea({
          start_at: this.startDateValue,
          end_at: this.endDateValue,
          sw_lat: bounds.minLat,
          sw_lng: bounds.minLng,
          ne_lat: bounds.maxLat,
          ne_lng: bounds.maxLng
        })
      ])

      console.log('[Maps V2] Found', points.length, 'points and', visits.length, 'visits in area')

      if (points.length === 0 && visits.length === 0) {
        Toast.info('No data found in selected area')
        this.cancelAreaSelection()
        return
      }

      // Convert points to GeoJSON and display
      if (points.length > 0) {
        const geojson = pointsToGeoJSON(points)
        this.selectedPointsLayer.updateSelectedPoints(geojson)
        this.selectedPointsLayer.show()
      }

      // Display visits in side panel and on map
      if (visits.length > 0) {
        this.displaySelectedVisits(visits)
      }

      // Update UI - show action buttons
      if (this.hasSelectionActionsTarget) {
        this.selectionActionsTarget.classList.remove('hidden')
      }

      // Update delete button text with count
      if (this.hasDeleteButtonTextTarget) {
        this.deleteButtonTextTarget.textContent = `Delete ${points.length} Point${points.length === 1 ? '' : 's'}`
      }

      // Disable selection mode
      this.selectionLayer.disableSelectionMode()

      const messages = []
      if (points.length > 0) messages.push(`${points.length} point${points.length === 1 ? '' : 's'}`)
      if (visits.length > 0) messages.push(`${visits.length} visit${visits.length === 1 ? '' : 's'}`)

      Toast.success(`Selected ${messages.join(' and ')}`)
    } catch (error) {
      console.error('[Maps V2] Failed to fetch data in area:', error)
      Toast.error('Failed to fetch data in selected area')
      this.cancelAreaSelection()
    }
  }

  /**
   * Display selected visits in side panel
   */
  displaySelectedVisits(visits) {
    if (!this.hasSelectedVisitsContainerTarget) return

    // Store visits for later use
    this.selectedVisits = visits
    this.selectedVisitIds = new Set()

    // Generate HTML for all visit cards
    const cardsHTML = visits.map(visit =>
      VisitCard.create(visit, {
        isSelected: false
      })
    ).join('')

    // Update container
    this.selectedVisitsContainerTarget.innerHTML = `
      <div class="selected-visits-list">
        <div class="flex items-center gap-2 mb-3 pb-2 border-b border-base-300">
          <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5 text-primary" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z" />
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 11a3 3 0 11-6 0 3 3 0 016 0z" />
          </svg>
          <h3 class="text-sm font-bold">Visits in Area (${visits.length})</h3>
        </div>
        ${cardsHTML}
      </div>
    `

    // Show container
    this.selectedVisitsContainerTarget.classList.remove('hidden')

    // Attach event listeners
    this.attachVisitCardListeners()

    // Update bulk actions after DOM updates (removes them if no visits selected)
    requestAnimationFrame(() => {
      this.updateBulkActions()
    })
  }

  /**
   * Attach event listeners to visit cards
   */
  attachVisitCardListeners() {
    // Checkbox selection
    this.element.querySelectorAll('[data-visit-select]').forEach(checkbox => {
      checkbox.addEventListener('change', (e) => {
        const visitId = parseInt(e.target.dataset.visitSelect)
        if (e.target.checked) {
          this.selectedVisitIds.add(visitId)
        } else {
          this.selectedVisitIds.delete(visitId)
        }
        this.updateBulkActions()
      })
    })

    // Confirm button
    this.element.querySelectorAll('[data-visit-confirm]').forEach(btn => {
      btn.addEventListener('click', async (e) => {
        const button = e.currentTarget
        const visitId = parseInt(button.dataset.visitConfirm)
        await this.confirmVisit(visitId)
      })
    })

    // Decline button
    this.element.querySelectorAll('[data-visit-decline]').forEach(btn => {
      btn.addEventListener('click', async (e) => {
        const button = e.currentTarget
        const visitId = parseInt(button.dataset.visitDecline)
        await this.declineVisit(visitId)
      })
    })
  }

  /**
   * Update bulk action buttons visibility and attach listeners
   */
  updateBulkActions() {
    const selectedCount = this.selectedVisitIds.size

    // Remove any existing bulk action buttons from visit cards
    const existingBulkActions = this.element.querySelectorAll('.bulk-actions-inline')
    existingBulkActions.forEach(el => el.remove())

    if (selectedCount >= 2) {
      // Find the last (lowest) selected visit card
      const selectedVisitCards = Array.from(this.element.querySelectorAll('.visit-card'))
        .filter(card => {
          const visitId = parseInt(card.dataset.visitId)
          return this.selectedVisitIds.has(visitId)
        })

      if (selectedVisitCards.length > 0) {
        const lastSelectedCard = selectedVisitCards[selectedVisitCards.length - 1]

        // Create bulk actions element
        const bulkActionsDiv = document.createElement('div')
        bulkActionsDiv.className = 'bulk-actions-inline mb-2'
        bulkActionsDiv.innerHTML = `
          <div class="bg-primary/10 border-2 border-primary border-dashed rounded-lg p-3">
            <div class="text-xs font-semibold mb-2 text-primary flex items-center gap-2">
              <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
              <span>${selectedCount} visit${selectedCount === 1 ? '' : 's'} selected</span>
            </div>
            <div class="grid grid-cols-3 gap-1.5">
              <button class="btn btn-xs btn-outline normal-case" data-bulk-merge>
                <svg xmlns="http://www.w3.org/2000/svg" class="h-3 w-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7h12m0 0l-4-4m4 4l-4 4m0 6H4m0 0l4 4m-4-4l4-4" />
                </svg>
                Merge
              </button>
              <button class="btn btn-xs btn-primary normal-case" data-bulk-confirm>
                <svg xmlns="http://www.w3.org/2000/svg" class="h-3 w-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
                </svg>
                Confirm
              </button>
              <button class="btn btn-xs btn-outline btn-error normal-case" data-bulk-decline>
                <svg xmlns="http://www.w3.org/2000/svg" class="h-3 w-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                </svg>
                Decline
              </button>
            </div>
          </div>
        `

        // Insert after the last selected card
        lastSelectedCard.insertAdjacentElement('afterend', bulkActionsDiv)

        // Attach listeners
        const mergeBtn = bulkActionsDiv.querySelector('[data-bulk-merge]')
        const confirmBtn = bulkActionsDiv.querySelector('[data-bulk-confirm]')
        const declineBtn = bulkActionsDiv.querySelector('[data-bulk-decline]')

        if (mergeBtn) {
          mergeBtn.addEventListener('click', () => this.bulkMergeVisits())
        }
        if (confirmBtn) {
          confirmBtn.addEventListener('click', () => this.bulkConfirmVisits())
        }
        if (declineBtn) {
          declineBtn.addEventListener('click', () => this.bulkDeclineVisits())
        }
      }
    }
  }

  /**
   * Confirm a single visit
   */
  async confirmVisit(visitId) {
    try {
      await this.api.updateVisitStatus(visitId, 'confirmed')
      Toast.success('Visit confirmed')
      // Refresh the visit card
      await this.refreshSelectedVisits()
    } catch (error) {
      console.error('[Maps V2] Failed to confirm visit:', error)
      Toast.error('Failed to confirm visit')
    }
  }

  /**
   * Decline a single visit
   */
  async declineVisit(visitId) {
    try {
      await this.api.updateVisitStatus(visitId, 'declined')
      Toast.success('Visit declined')
      // Refresh the visit card
      await this.refreshSelectedVisits()
    } catch (error) {
      console.error('[Maps V2] Failed to decline visit:', error)
      Toast.error('Failed to decline visit')
    }
  }

  /**
   * Bulk merge selected visits
   */
  async bulkMergeVisits() {
    const visitIds = Array.from(this.selectedVisitIds)

    if (visitIds.length < 2) {
      Toast.error('Select at least 2 visits to merge')
      return
    }

    if (!confirm(`Merge ${visitIds.length} visits into one?`)) {
      return
    }

    try {
      Toast.info('Merging visits...')
      const mergedVisit = await this.api.mergeVisits(visitIds)
      Toast.success('Visits merged successfully')

      // Clear selection state
      this.selectedVisitIds.clear()

      // Remove the old visit cards and add the merged one
      this.replaceVisitsWithMerged(visitIds, mergedVisit)

      // Update bulk actions (will remove the panel since selection is cleared)
      this.updateBulkActions()
    } catch (error) {
      console.error('[Maps V2] Failed to merge visits:', error)
      Toast.error('Failed to merge visits')
    }
  }

  /**
   * Bulk confirm selected visits
   */
  async bulkConfirmVisits() {
    const visitIds = Array.from(this.selectedVisitIds)

    try {
      Toast.info('Confirming visits...')
      await this.api.bulkUpdateVisits(visitIds, 'confirmed')
      Toast.success(`Confirmed ${visitIds.length} visits`)

      // Clear selection state before refreshing
      this.selectedVisitIds.clear()

      await this.refreshSelectedVisits()
    } catch (error) {
      console.error('[Maps V2] Failed to confirm visits:', error)
      Toast.error('Failed to confirm visits')
    }
  }

  /**
   * Bulk decline selected visits
   */
  async bulkDeclineVisits() {
    const visitIds = Array.from(this.selectedVisitIds)

    if (!confirm(`Decline ${visitIds.length} visits?`)) {
      return
    }

    try {
      Toast.info('Declining visits...')
      await this.api.bulkUpdateVisits(visitIds, 'declined')
      Toast.success(`Declined ${visitIds.length} visits`)

      // Clear selection state before refreshing
      this.selectedVisitIds.clear()

      await this.refreshSelectedVisits()
    } catch (error) {
      console.error('[Maps V2] Failed to decline visits:', error)
      Toast.error('Failed to decline visits')
    }
  }

  /**
   * Replace merged visit cards with the new merged visit
   */
  replaceVisitsWithMerged(oldVisitIds, mergedVisit) {
    const container = this.element.querySelector('.selected-visits-list')
    if (!container) return

    // Find the correct position to insert BEFORE removing old cards
    const mergedStartTime = new Date(mergedVisit.started_at).getTime()
    const allCards = Array.from(container.querySelectorAll('.visit-card'))

    let insertBeforeCard = null
    for (const card of allCards) {
      const cardId = parseInt(card.dataset.visitId)

      // Skip cards that we're about to remove
      if (oldVisitIds.includes(cardId)) continue

      // Find the visit data for this card
      const cardVisit = this.selectedVisits.find(v => v.id === cardId)
      if (cardVisit) {
        const cardStartTime = new Date(cardVisit.started_at).getTime()
        if (cardStartTime > mergedStartTime) {
          insertBeforeCard = card
          break
        }
      }
    }

    // Remove old visit cards from DOM
    oldVisitIds.forEach(id => {
      const card = this.element.querySelector(`.visit-card[data-visit-id="${id}"]`)
      if (card) {
        card.remove()
      }
    })

    // Update the selectedVisits array and sort by started_at
    this.selectedVisits = this.selectedVisits.filter(v => !oldVisitIds.includes(v.id))
    this.selectedVisits.push(mergedVisit)
    this.selectedVisits.sort((a, b) => new Date(a.started_at) - new Date(b.started_at))

    // Create new visit card HTML
    const newCardHTML = VisitCard.create(mergedVisit, { isSelected: false })

    // Insert the new card in the correct position
    if (insertBeforeCard) {
      insertBeforeCard.insertAdjacentHTML('beforebegin', newCardHTML)
    } else {
      // If no card starts after this one, append to the end
      container.insertAdjacentHTML('beforeend', newCardHTML)
    }

    // Update header count
    const header = container.querySelector('h3')
    if (header) {
      header.textContent = `Visits in Area (${this.selectedVisits.length})`
    }

    // Attach event listeners to the new card
    this.attachVisitCardListeners()
  }

  /**
   * Refresh selected visits after changes
   */
  async refreshSelectedVisits() {
    // Re-fetch visits in the same area
    const bounds = this.selectionLayer.currentRect
    if (!bounds) return

    try {
      const visits = await this.api.fetchVisitsInArea({
        start_at: this.startDateValue,
        end_at: this.endDateValue,
        sw_lat: bounds.start.lat < bounds.end.lat ? bounds.start.lat : bounds.end.lat,
        sw_lng: bounds.start.lng < bounds.end.lng ? bounds.start.lng : bounds.end.lng,
        ne_lat: bounds.start.lat > bounds.end.lat ? bounds.start.lat : bounds.end.lat,
        ne_lng: bounds.start.lng > bounds.end.lng ? bounds.start.lng : bounds.end.lng
      })

      this.displaySelectedVisits(visits)
    } catch (error) {
      console.error('[Maps V2] Failed to refresh visits:', error)
    }
  }

  /**
   * Cancel area selection
   */
  cancelAreaSelection() {
    console.log('[Maps V2] Cancelling area selection')

    // Clear selection layers
    if (this.selectionLayer) {
      this.selectionLayer.disableSelectionMode()
      this.selectionLayer.clearSelection()
    }

    if (this.selectedPointsLayer) {
      this.selectedPointsLayer.clearSelection()
    }

    // Clear visits
    if (this.hasSelectedVisitsContainerTarget) {
      this.selectedVisitsContainerTarget.classList.add('hidden')
      this.selectedVisitsContainerTarget.innerHTML = ''
    }

    if (this.hasSelectedVisitsBulkActionsTarget) {
      this.selectedVisitsBulkActionsTarget.classList.add('hidden')
    }

    // Clear stored data
    this.selectedVisits = []
    this.selectedVisitIds = new Set()

    // Update UI - restore Select Area button
    if (this.hasSelectAreaButtonTarget) {
      this.selectAreaButtonTarget.innerHTML = `
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="w-5 h-5">
          <rect x="3" y="3" width="18" height="18" rx="2" ry="2"></rect>
          <path d="M9 3v18"></path>
          <path d="M15 3v18"></path>
          <path d="M3 9h18"></path>
          <path d="M3 15h18"></path>
        </svg>
        Select Area
      `
      this.selectAreaButtonTarget.classList.remove('btn-error')
      this.selectAreaButtonTarget.classList.add('btn', 'btn-outline')
      // Restore original action
      this.selectAreaButtonTarget.dataset.action = 'click->maps-v2#startSelectArea'
    }

    if (this.hasSelectionActionsTarget) {
      this.selectionActionsTarget.classList.add('hidden')
    }

    Toast.info('Selection cancelled')
  }

  /**
   * Delete selected points
   */
  async deleteSelectedPoints() {
    const pointCount = this.selectedPointsLayer.getCount()
    const pointIds = this.selectedPointsLayer.getSelectedPointIds()

    if (pointIds.length === 0) {
      Toast.error('No points selected')
      return
    }

    // Confirm deletion
    const confirmed = confirm(
      `Are you sure you want to delete ${pointCount} point${pointCount === 1 ? '' : 's'}? This action cannot be undone.`
    )

    if (!confirmed) {
      return
    }

    console.log('[Maps V2] Deleting', pointIds.length, 'points')

    try {
      Toast.info('Deleting points...')

      // Call bulk delete API
      const result = await this.api.bulkDeletePoints(pointIds)

      console.log('[Maps V2] Deleted', result.count, 'points')

      // Clear selection first
      this.cancelAreaSelection()

      // Reload map data silently (no loading overlay, no camera movement, no success toast)
      await this.loadMapData({
        showLoading: false,
        fitBounds: false,
        showToast: false
      })

      // Show success toast after reload
      Toast.success(`Deleted ${result.count} point${result.count === 1 ? '' : 's'}`)
    } catch (error) {
      console.error('[Maps V2] Failed to delete points:', error)
      Toast.error('Failed to delete points. Please try again.')
    }
  }
}
