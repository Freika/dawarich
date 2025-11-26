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
    'fogToggle',
    'scratchToggle',
    // Speed-colored routes
    'routesOptions',
    'speedColoredToggle',
    'speedColorScaleContainer',
    'speedColorScaleInput'
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

      // Convert to GeoJSON
      const visitsGeoJSON = this.dataLoader.visitsToGeoJSON(visits)

      // Update visits layer
      this.layerManager.updateLayer('visits', visitsGeoJSON)

      console.log('[Maps V2] Visits reloaded successfully')
    } catch (error) {
      console.error('[Maps V2] Failed to reload visits:', error)
    }
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
}
