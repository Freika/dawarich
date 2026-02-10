import { Controller } from "@hotwired/stimulus"
import { Toast } from "maps_maplibre/components/toast"
import { TimelineManager } from "maps_maplibre/managers/timeline_manager"
import { ApiClient } from "maps_maplibre/services/api_client"
import { CleanupHelper } from "maps_maplibre/utils/cleanup_helper"
import { performanceMonitor } from "maps_maplibre/utils/performance_monitor"
import { SearchManager } from "maps_maplibre/utils/search_manager"
import { SettingsManager } from "maps_maplibre/utils/settings_manager"
import { AreaSelectionManager } from "./maplibre/area_selection_manager"
import { DataLoader } from "./maplibre/data_loader"
import { DateManager } from "./maplibre/date_manager"
import { EventHandlers } from "./maplibre/event_handlers"
import { FilterManager } from "./maplibre/filter_manager"
import { LayerManager } from "./maplibre/layer_manager"
import { MapDataManager } from "./maplibre/map_data_manager"
import { MapInitializer } from "./maplibre/map_initializer"
import { PlacesManager } from "./maplibre/places_manager"
import { RoutesManager } from "./maplibre/routes_manager"
import { SettingsController } from "./maplibre/settings_manager"
import { VisitsManager } from "./maplibre/visits_manager"

/**
 * Main map controller for Maps V2
 * Coordinates between different managers and handles UI interactions
 */
export default class extends Controller {
  static values = {
    apiKey: String,
    startDate: String,
    endDate: String,
    timezone: String,
  }

  static targets = [
    "container",
    "progressBadge",
    "progressBadgeText",
    "monthSelect",
    "clusterToggle",
    "settingsPanel",
    "visitsSearch",
    "routeOpacityRange",
    "placesFilters",
    "enableAllPlaceTagsToggle",
    "fogRadiusValue",
    "fogThresholdValue",
    "metersBetweenValue",
    "minutesBetweenValue",
    "minMinutesInCityValue",
    "maxGapMinutesValue",
    // Search
    "searchInput",
    "searchResults",
    // Layer toggles
    "pointsToggle",
    "routesToggle",
    "heatmapToggle",
    "visitsToggle",
    "photosToggle",
    "areasToggle",
    "placesToggle",
    "fogToggle",
    "scratchToggle",
    "familyToggle",
    // Speed-colored routes
    "routesOptions",
    "speedColoredToggle",
    "speedColorScaleContainer",
    "speedColorScaleInput",
    // Globe projection
    "globeToggle",
    // Family members
    "familyMembersList",
    "familyMembersContainer",
    // Area selection
    "selectAreaButton",
    "selectionActions",
    "deleteButtonText",
    "selectedVisitsContainer",
    "selectedVisitsBulkActions",
    // Info display
    "infoDisplay",
    "infoTitle",
    "infoContent",
    "infoActions",
    // Route info template
    "routeInfoTemplate",
    "routeStartTime",
    "routeEndTime",
    "routeDuration",
    "routeDistance",
    "routeSpeed",
    "routeSpeedContainer",
    "routePoints",
    // Transportation mode thresholds
    "transportationCollapseToggle",
    "transportationExpertToggle",
    "transportationBasicSettings",
    "transportationExpertSettings",
    // Transportation speed inputs
    "walkingMaxSpeedInput",
    "cyclingMaxSpeedInput",
    "drivingMaxSpeedInput",
    "flyingMinSpeedInput",
    // Transportation speed value displays
    "walkingMaxSpeedValue",
    "cyclingMaxSpeedValue",
    "drivingMaxSpeedValue",
    "flyingMinSpeedValue",
    // Transportation expert inputs
    "stationaryMaxSpeedInput",
    "trainMinSpeedInput",
    "runningVsCyclingAccelInput",
    "cyclingVsDrivingAccelInput",
    "minSegmentDurationInput",
    "timeGapThresholdInput",
    "minFlightDistanceInput",
    // Transportation expert value displays
    "stationaryMaxSpeedValue",
    "trainMinSpeedValue",
    "runningVsCyclingAccelValue",
    "cyclingVsDrivingAccelValue",
    "minSegmentDurationValue",
    "timeGapThresholdValue",
    "minFlightDistanceValue",
    // Transportation unit labels
    "speedUnitLabel",
    "distanceUnitLabel",
    // Transportation recalculation status
    "transportationRecalculationAlert",
    "transportationLockedMessage",
    // Transportation apply button
    "transportationApplyButton",
    "transportationDirtyMessage",
    // Timeline
    "timelinePanel",
    "timelineScrubber",
    "timelineScrubberTrack",
    "timelineDensityContainer",
    "timelineDayDisplay",
    "timelineDayCount",
    "timelineTimeDisplay",
    "timelineDataIndicator",
    "timelineCycleControls",
    "timelinePointCounter",
    "timelinePrevDayButton",
    "timelineNextDayButton",
    // Timeline replay
    "timelinePlayButton",
    "timelinePlayIcon",
    "timelinePauseIcon",
    "timelineSpeedSlider",
    "timelineSpeedLabel",
    // Timeline speed display (velocity)
    "timelineSpeedDisplay",
    // WebGL error
    "webglError",
  ]

  async connect() {
    if (!this.isWebGLSupported()) {
      this.showWebGLError()
      return
    }

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
    this.dataLoader = new DataLoader(this.api, this.apiKeyValue, this.settings)
    this.eventHandlers = new EventHandlers(this.map, this)
    this.filterManager = new FilterManager(this.dataLoader)
    this.mapDataManager = new MapDataManager(this)

    // Initialize feature managers
    this.areaSelectionManager = new AreaSelectionManager(this)
    this.visitsManager = new VisitsManager(this)
    this.placesManager = new PlacesManager(this)
    this.routesManager = new RoutesManager(this)

    // Initialize search manager
    this.initializeSearch()

    // Listen for visit and place creation/update events
    this.boundHandleVisitCreated = this.visitsManager.handleVisitCreated.bind(
      this.visitsManager,
    )
    this.cleanup.addEventListener(
      document,
      "visit:created",
      this.boundHandleVisitCreated,
    )

    this.boundHandleVisitUpdated = this.visitsManager.handleVisitUpdated.bind(
      this.visitsManager,
    )
    this.cleanup.addEventListener(
      document,
      "visit:updated",
      this.boundHandleVisitUpdated,
    )

    this.boundHandlePlaceCreated = this.placesManager.handlePlaceCreated.bind(
      this.placesManager,
    )
    this.cleanup.addEventListener(
      document,
      "place:created",
      this.boundHandlePlaceCreated,
    )

    this.boundHandlePlaceUpdated = this.placesManager.handlePlaceUpdated.bind(
      this.placesManager,
    )
    this.cleanup.addEventListener(
      document,
      "place:updated",
      this.boundHandlePlaceUpdated,
    )

    this.boundHandleAreaCreated = this.handleAreaCreated.bind(this)
    this.cleanup.addEventListener(
      document,
      "area:created",
      this.boundHandleAreaCreated,
    )

    // Format initial dates
    this.startDateValue = DateManager.formatDateForAPI(
      new Date(this.startDateValue),
    )
    this.endDateValue = DateManager.formatDateForAPI(
      new Date(this.endDateValue),
    )

    this.loadMapData()
  }

  disconnect() {
    this._stopTimelineReplay()
    this.settingsController?.stopRecalculationPolling()
    this.searchManager?.destroy()
    this.cleanup.cleanup()
    this.map?.remove()
    performanceMonitor.logReport()
  }

  isWebGLSupported() {
    try {
      const canvas = document.createElement("canvas")
      return !!(canvas.getContext("webgl2") || canvas.getContext("webgl"))
    } catch {
      return false
    }
  }

  showWebGLError() {
    this.containerTarget.classList.add("hidden")
    this.webglErrorTarget.classList.remove("hidden")
  }

  /**
   * Initialize MapLibre map
   */
  async initializeMap() {
    this.map = await MapInitializer.initialize(this.containerTarget, {
      mapStyle: this.settings.mapStyle,
      globeProjection: this.settings.globeProjection,
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
      console.warn(
        "[Maps V2] Search targets not found, search functionality disabled",
      )
      return
    }

    this.searchManager = new SearchManager(this.map, this.apiKeyValue)
    this.searchManager.initialize(
      this.searchInputTarget,
      this.searchResultsTarget,
    )
  }

  /**
   * Load map data from API
   */
  async loadMapData(options = {}) {
    return this.mapDataManager.loadMapData(
      this.startDateValue,
      this.endDateValue,
      options,
    )
  }

  /**
   * Month selector changed
   */
  monthChanged(event) {
    const { startDate, endDate } = DateManager.parseMonthSelector(
      event.target.value,
    )
    this.startDateValue = startDate
    this.endDateValue = endDate

    this.loadMapData()
  }

  /**
   * Show loading progress badge
   */
  showProgress() {
    this._lastSourceCount = 0
    if (this.hasProgressBadgeTarget) {
      this.progressBadgeTarget.classList.remove("complete", "pop")
      this.progressBadgeTarget.classList.add("visible")
    }
    if (this.hasProgressBadgeTextTarget) {
      this.progressBadgeTextTarget.textContent = "Loading..."
    }
  }

  /**
   * Hide loading progress badge with fade-out
   */
  hideProgress() {
    if (!this.hasProgressBadgeTarget) return
    const badge = this.progressBadgeTarget
    badge.classList.remove("visible")
  }

  /**
   * Show loading indicator (alias for showProgress)
   */
  showLoading() {
    this.showProgress()
  }

  /**
   * Hide loading indicator (alias for hideProgress)
   */
  hideLoading() {
    this.hideProgress()
  }

  /**
   * Update loading counts badge
   */
  updateLoadingCounts({ counts, isComplete }) {
    this._lastLoadingCounts = counts
    this._renderLoadingBadge(isComplete)
  }

  /**
   * Render the loading badge text from current counts
   * @private
   */
  _renderLoadingBadge(isComplete = false) {
    if (!this.hasProgressBadgeTextTarget) return

    const counts = this._lastLoadingCounts || {}
    const parts = []
    for (const [source, count] of Object.entries(counts)) {
      parts.push(`${count.toLocaleString()} ${source}`)
    }

    // Append family count if family layer is enabled
    if (this.settings?.familyEnabled) {
      const familyCount = this._familyMemberCount || 0
      parts.push(`${familyCount.toLocaleString()} family`)
    }

    // Detect when a new data source appears and trigger a pop animation
    const sourceCount = parts.length
    if (
      this.hasProgressBadgeTarget &&
      sourceCount > (this._lastSourceCount || 0)
    ) {
      const badge = this.progressBadgeTarget
      badge.classList.remove("pop")
      // Force reflow so re-adding the class restarts the animation
      void badge.offsetWidth
      badge.classList.add("pop")
    }
    this._lastSourceCount = sourceCount

    this.progressBadgeTextTarget.textContent =
      parts.length > 0 ? parts.join(" \u00B7 ") : "Loading..."

    if (isComplete) {
      if (this.hasProgressBadgeTarget) {
        this.progressBadgeTarget.classList.add("complete")
      }
      this._lastSourceCount = 0
      setTimeout(() => this.hideProgress(), 1200)
    }
  }

  /**
   * Toggle settings panel
   */
  toggleSettings() {
    if (this.hasSettingsPanelTarget) {
      this.settingsPanelTarget.classList.toggle("open")
    }
  }

  // ===== Delegated Methods to Managers =====

  // Settings Controller methods
  updateMapStyle(event) {
    return this.settingsController.updateMapStyle(event)
  }
  resetSettings() {
    return this.settingsController.resetSettings()
  }
  updateRouteOpacity(event) {
    return this.settingsController.updateRouteOpacity(event)
  }
  updateAdvancedSettings(event) {
    return this.settingsController.updateAdvancedSettings(event)
  }
  updateFogRadiusDisplay(event) {
    return this.settingsController.updateFogRadiusDisplay(event)
  }
  updateFogThresholdDisplay(event) {
    return this.settingsController.updateFogThresholdDisplay(event)
  }
  updateMetersBetweenDisplay(event) {
    return this.settingsController.updateMetersBetweenDisplay(event)
  }
  updateMinutesBetweenDisplay(event) {
    return this.settingsController.updateMinutesBetweenDisplay(event)
  }
  updateMinMinutesInCityDisplay(event) {
    return this.settingsController.updateMinMinutesInCityDisplay(event)
  }
  updateMaxGapMinutesDisplay(event) {
    return this.settingsController.updateMaxGapMinutesDisplay(event)
  }
  toggleGlobe(event) {
    return this.settingsController.toggleGlobe(event)
  }
  toggleTransportationExpertMode(event) {
    return this.settingsController.toggleTransportationExpertMode(event)
  }
  updateTransportationThresholdDisplay(event) {
    return this.settingsController.updateTransportationThresholdDisplay(event)
  }
  markTransportationSettingsDirty(event) {
    return this.settingsController.markTransportationSettingsDirty(event)
  }
  applyTransportationSettings(event) {
    return this.settingsController.applyTransportationSettings(event)
  }

  // Area Selection Manager methods
  startSelectArea() {
    return this.areaSelectionManager.startSelectArea()
  }
  cancelAreaSelection() {
    return this.areaSelectionManager.cancelAreaSelection()
  }
  deleteSelectedPoints() {
    return this.areaSelectionManager.deleteSelectedPoints()
  }

  // Visits Manager methods
  toggleVisits(event) {
    return this.visitsManager.toggleVisits(event)
  }
  searchVisits(event) {
    return this.visitsManager.searchVisits(event)
  }
  filterVisits(event) {
    return this.visitsManager.filterVisits(event)
  }
  startCreateVisit() {
    return this.visitsManager.startCreateVisit()
  }

  // Places Manager methods
  togglePlaces(event) {
    return this.placesManager.togglePlaces(event)
  }
  filterPlacesByTags(event) {
    return this.placesManager.filterPlacesByTags(event)
  }
  toggleAllPlaceTags(event) {
    return this.placesManager.toggleAllPlaceTags(event)
  }
  startCreatePlace() {
    return this.placesManager.startCreatePlace()
  }

  // Area creation
  startCreateArea() {
    if (
      this.hasSettingsPanelTarget &&
      this.settingsPanelTarget.classList.contains("open")
    ) {
      this.toggleSettings()
    }

    // Find area drawer controller on the same element
    const drawerController =
      this.application.getControllerForElementAndIdentifier(
        this.element,
        "area-drawer",
      )

    if (drawerController) {
      drawerController.startDrawing(this.map)
    } else {
      Toast.error("Area drawer controller not available")
    }
  }

  async handleAreaCreated(_event) {
    try {
      // Fetch all areas from API
      const areas = await this.api.fetchAreas()

      // Convert to GeoJSON
      const areasGeoJSON = this.dataLoader.areasToGeoJSON(areas)

      // Get or create the areas layer
      let areasLayer = this.layerManager.getLayer("areas")

      if (areasLayer) {
        // Update existing layer
        areasLayer.update(areasGeoJSON)
      } else {
        // Create the layer if it doesn't exist yet
        console.log("[Maps V2] Creating areas layer")
        this.layerManager._addAreasLayer(areasGeoJSON)
        areasLayer = this.layerManager.getLayer("areas")
        console.log(
          "[Maps V2] Areas layer created, visible?",
          areasLayer?.visible,
        )
      }

      // Enable the layer if it wasn't already
      if (areasLayer) {
        if (!areasLayer.visible) {
          areasLayer.show()
          this.settings.layers.areas = true
          this.settingsController.saveSetting("layers.areas", true)

          // Update toggle state
          if (this.hasAreasToggleTarget) {
            this.areasToggleTarget.checked = true
          }
        } else {
          console.log("[Maps V2] Areas layer already visible")
        }
      }

      Toast.success("Area created successfully!")
    } catch (_error) {
      Toast.error("Failed to reload areas")
    }
  }

  // Routes Manager methods
  togglePoints(event) {
    return this.routesManager.togglePoints(event)
  }
  toggleRoutes(event) {
    return this.routesManager.toggleRoutes(event)
  }
  toggleHeatmap(event) {
    return this.routesManager.toggleHeatmap(event)
  }
  toggleFog(event) {
    return this.routesManager.toggleFog(event)
  }
  toggleScratch(event) {
    return this.routesManager.toggleScratch(event)
  }
  togglePhotos(event) {
    return this.routesManager.togglePhotos(event)
  }
  toggleAreas(event) {
    return this.routesManager.toggleAreas(event)
  }
  toggleTracks(event) {
    return this.routesManager.toggleTracks(event)
  }
  toggleSpeedColoredRoutes(event) {
    return this.routesManager.toggleSpeedColoredRoutes(event)
  }
  openSpeedColorEditor() {
    return this.routesManager.openSpeedColorEditor()
  }
  handleSpeedColorSave(event) {
    return this.routesManager.handleSpeedColorSave(event)
  }
  toggleFamily(event) {
    return this.routesManager.toggleFamily(event)
  }

  // Family Members methods
  async loadFamilyMembers() {
    try {
      this.showProgress()
      this.updateLoadingCounts({
        counts: { family: 0 },
        isComplete: false,
      })

      const response = await fetch(
        `/api/v1/families/locations?api_key=${this.apiKeyValue}`,
        {
          headers: {
            Accept: "application/json",
            "Content-Type": "application/json",
          },
        },
      )

      if (!response.ok) {
        if (response.status === 403) {
          Toast.info("Family feature not available")
          this.updateLoadingCounts({
            counts: { family: 0 },
            isComplete: true,
          })
          return
        }
        throw new Error(`HTTP error! status: ${response.status}`)
      }

      const data = await response.json()
      const locations = data.locations || []

      // Update family layer with locations
      const familyLayer = this.layerManager.getLayer("family")
      if (familyLayer) {
        familyLayer.loadMembers(locations)
      }

      // Update family count in badge
      this._familyMemberCount = locations.length
      this.updateLoadingCounts({
        counts: { family: locations.length },
        isComplete: true,
      })

      // Render family members list
      this.renderFamilyMembersList(locations)

      Toast.success(`Loaded ${locations.length} family member(s)`)
    } catch (error) {
      console.error("[Maps V2] Failed to load family members:", error)
      Toast.error("Failed to load family members")
    }
  }

  renderFamilyMembersList(locations) {
    if (!this.hasFamilyMembersContainerTarget) return

    const container = this.familyMembersContainerTarget

    if (locations.length === 0) {
      container.innerHTML =
        '<p class="text-xs text-base-content/60">No family members sharing location</p>'
      return
    }

    container.innerHTML = locations
      .map((location) => {
        const emailInitial = location.email?.charAt(0)?.toUpperCase() || "?"
        const color = this.getFamilyMemberColor(location.user_id)
        const lastSeen = new Date(location.updated_at).toLocaleString("en-US", {
          timeZone: this.timezoneValue || "UTC",
          month: "short",
          day: "numeric",
          hour: "numeric",
          minute: "2-digit",
        })

        return `
        <div class="flex items-center gap-2 p-2 hover:bg-base-200 rounded-lg cursor-pointer transition-colors"
             data-action="click->maps--maplibre#centerOnFamilyMember"
             data-member-id="${location.user_id}">
          <div style="background-color: ${color}; color: white; border-radius: 50%; width: 24px; height: 24px; display: flex; align-items: center; justify-content: center; font-size: 12px; font-weight: bold; flex-shrink: 0;">
            ${emailInitial}
          </div>
          <div class="flex-1 min-w-0">
            <div class="text-sm font-medium truncate">${location.email || "Unknown"}</div>
            <div class="text-xs text-base-content/60">${lastSeen}</div>
          </div>
        </div>
      `
      })
      .join("")
  }

  getFamilyMemberColor(userId) {
    const colors = [
      "#3b82f6",
      "#10b981",
      "#f59e0b",
      "#ef4444",
      "#8b5cf6",
      "#ec4899",
    ]
    // Use user ID to get consistent color
    const hash = userId
      .toString()
      .split("")
      .reduce((acc, char) => acc + char.charCodeAt(0), 0)
    return colors[hash % colors.length]
  }

  centerOnFamilyMember(event) {
    const memberId = event.currentTarget.dataset.memberId
    if (!memberId) return

    const familyLayer = this.layerManager.getLayer("family")
    if (familyLayer) {
      familyLayer.centerOnMember(parseInt(memberId, 10))
      Toast.success("Centered on family member")
    }
  }

  // Info Display methods
  showInfo(title, content, actions = []) {
    if (!this.hasInfoDisplayTarget) return

    // Set title
    this.infoTitleTarget.textContent = title

    // Set content
    this.infoContentTarget.innerHTML = content

    // Set actions
    if (actions.length > 0) {
      this.infoActionsTarget.innerHTML = actions
        .map((action) => {
          if (action.type === "button") {
            // For button actions (modals, etc.), create a button with data-action
            // Use error styling for delete buttons
            const buttonClass =
              action.label === "Delete"
                ? "btn btn-sm btn-error"
                : "btn btn-sm btn-primary"
            return `<button class="${buttonClass}" data-action="click->maps--maplibre#${action.handler}" data-id="${action.id}" data-entity-type="${action.entityType}">${action.label}</button>`
          } else {
            // For link actions, keep the original behavior
            return `<a href="${action.url}" class="btn btn-sm btn-primary">${action.label}</a>`
          }
        })
        .join("")
    } else {
      this.infoActionsTarget.innerHTML = ""
    }

    // Show info display
    this.infoDisplayTarget.classList.remove("hidden")

    // Switch to tools tab and open panel
    this.switchToToolsTab()
  }

  showRouteInfo(routeData) {
    if (!this.hasRouteInfoTemplateTarget) return

    // Clone the template
    const template = this.routeInfoTemplateTarget.content.cloneNode(true)

    // Populate the template with data
    const fragment = document.createDocumentFragment()
    fragment.appendChild(template)

    fragment.querySelector(
      '[data-maps--maplibre-target="routeStartTime"]',
    ).textContent = routeData.startTime
    fragment.querySelector(
      '[data-maps--maplibre-target="routeEndTime"]',
    ).textContent = routeData.endTime
    fragment.querySelector(
      '[data-maps--maplibre-target="routeDuration"]',
    ).textContent = routeData.duration
    fragment.querySelector(
      '[data-maps--maplibre-target="routeDistance"]',
    ).textContent = routeData.distance
    fragment.querySelector(
      '[data-maps--maplibre-target="routePoints"]',
    ).textContent = routeData.pointCount

    // Handle optional speed field
    const speedContainer = fragment.querySelector(
      '[data-maps--maplibre-target="routeSpeedContainer"]',
    )
    if (routeData.speed) {
      fragment.querySelector(
        '[data-maps--maplibre-target="routeSpeed"]',
      ).textContent = routeData.speed
      speedContainer.style.display = ""
    } else {
      speedContainer.style.display = "none"
    }

    // Convert fragment to HTML string for showInfo
    const div = document.createElement("div")
    div.appendChild(fragment)

    this.showInfo("Route Information", div.innerHTML)
  }

  closeInfo() {
    if (!this.hasInfoDisplayTarget) return
    this.infoDisplayTarget.classList.add("hidden")

    // Clear the appropriate selection when info panel is closed
    // Only one type can be selected at a time
    if (this.eventHandlers) {
      if (this.eventHandlers.selectedTrackFeature) {
        this.eventHandlers.clearTrackSelection()
      } else if (this.eventHandlers.selectedRouteFeature) {
        this.eventHandlers.clearRouteSelection()
      }
    }
  }

  /**
   * Handle edit action from info display
   */
  handleEdit(event) {
    const button = event.currentTarget
    const id = button.dataset.id
    const entityType = button.dataset.entityType

    switch (entityType) {
      case "visit":
        this.openVisitModal(id)
        break
      case "place":
        this.openPlaceEditModal(id)
        break
      default:
        console.warn("[Maps V2] Unknown entity type:", entityType)
    }
  }

  /**
   * Handle delete action from info display
   */
  handleDelete(event) {
    const button = event.currentTarget
    const id = button.dataset.id
    const entityType = button.dataset.entityType

    switch (entityType) {
      case "area":
        this.deleteArea(id)
        break
      default:
        console.warn("[Maps V2] Unknown entity type for delete:", entityType)
    }
  }

  /**
   * Open visit edit modal
   */
  async openVisitModal(visitId) {
    try {
      // Fetch visit details
      const response = await fetch(`/api/v1/visits/${visitId}`, {
        headers: {
          Authorization: `Bearer ${this.apiKeyValue}`,
          "Content-Type": "application/json",
        },
      })

      if (!response.ok) {
        throw new Error(`Failed to fetch visit: ${response.status}`)
      }

      const visit = await response.json()

      // Trigger visit edit event
      const event = new CustomEvent("visit:edit", {
        detail: { visit },
        bubbles: true,
      })
      document.dispatchEvent(event)
    } catch (_error) {
      Toast.error("Failed to load visit details")
    }
  }

  /**
   * Delete area with confirmation
   */
  async deleteArea(areaId) {
    try {
      // Fetch area details
      const area = await this.api.fetchArea(areaId)

      // Show delete confirmation
      const confirmed = confirm(
        `Delete area "${area.name}"?\n\nThis action cannot be undone.`,
      )

      if (!confirmed) return

      Toast.info("Deleting area...")

      // Delete the area
      await this.api.deleteArea(areaId)

      // Reload areas
      const areas = await this.api.fetchAreas()
      const areasGeoJSON = this.dataLoader.areasToGeoJSON(areas)

      const areasLayer = this.layerManager.getLayer("areas")
      if (areasLayer) {
        areasLayer.update(areasGeoJSON)
      }

      // Close info display
      this.closeInfo()

      Toast.success("Area deleted successfully")
    } catch (_error) {
      Toast.error("Failed to delete area")
    }
  }

  /**
   * Open place edit modal
   */
  async openPlaceEditModal(placeId) {
    try {
      // Fetch place details
      const response = await fetch(`/api/v1/places/${placeId}`, {
        headers: {
          Authorization: `Bearer ${this.apiKeyValue}`,
          "Content-Type": "application/json",
        },
      })

      if (!response.ok) {
        throw new Error(`Failed to fetch place: ${response.status}`)
      }

      const place = await response.json()

      // Trigger place edit event
      const event = new CustomEvent("place:edit", {
        detail: { place },
        bubbles: true,
      })
      document.dispatchEvent(event)
    } catch (_error) {
      Toast.error("Failed to load place details")
    }
  }

  switchToToolsTab() {
    // Open the panel if it's not already open
    if (!this.settingsPanelTarget.classList.contains("open")) {
      this.toggleSettings()
    }

    // Find the map-panel controller and switch to tools tab
    const panelElement = this.settingsPanelTarget
    const panelController =
      this.application.getControllerForElementAndIdentifier(
        panelElement,
        "map-panel",
      )

    if (panelController?.switchToTab) {
      panelController.switchToTab("tools")
    }
  }

  // ===== Timeline Methods =====

  /**
   * Toggle timeline panel visibility
   */
  async toggleTimeline() {
    if (!this.hasTimelinePanelTarget) return

    const isVisible = !this.timelinePanelTarget.classList.contains("hidden")

    if (isVisible) {
      // Hide timeline
      this._stopTimelineReplay()
      this.timelinePanelTarget.classList.add("hidden")
      this._clearTimelineMarker()
      this._clearTimelineRouteHighlight()
      this._updateTimelineSpeedDisplay(null)
    } else {
      // Show timeline and initialize with loaded points
      await this._initializeTimeline()
      this.timelinePanelTarget.classList.remove("hidden")
    }
  }

  /**
   * Replay a specific track from its start time (triggered from track info card)
   */
  async replayTrack(event) {
    if (!this.hasTimelinePanelTarget) return

    // If replay is already active, pause it
    if (this.timelineReplayActive) {
      this._stopTimelineReplay()
      return
    }

    // If timeline is already visible and initialized, resume from current position
    const isVisible = !this.timelinePanelTarget.classList.contains("hidden")
    if (isVisible && this.timelineManager?.hasData()) {
      this._startTimelineReplay()
      this._updateTrackReplayButton(true)
      return
    }

    const trackStart = event.currentTarget.dataset.trackStart
    if (!trackStart) return

    const trackDate = new Date(trackStart)
    if (Number.isNaN(trackDate.getTime())) return

    // First time: initialize timeline and navigate to the track's day
    await this._initializeTimeline()
    this.timelinePanelTarget.classList.remove("hidden")

    if (!this.timelineManager?.hasData()) return

    // Navigate to the day matching the track's start
    const targetDay = `${trackDate.getFullYear()}-${String(trackDate.getMonth() + 1).padStart(2, "0")}-${String(trackDate.getDate()).padStart(2, "0")}`
    const dayIndex = this.timelineManager.availableDays.indexOf(targetDay)

    if (dayIndex >= 0 && dayIndex !== this.timelineManager.currentDayIndex) {
      this.timelineManager.currentDayIndex = dayIndex
      this.timelineManager.buildMinuteIndex()
      this._updateTimelineDayDisplay()
      this._updateTimelineDayCount()
      this._updateTimelineDayButtons()
      this._renderTimelineDensity()
    }

    // Set scrubber to the track's start minute
    const startMinute = trackDate.getHours() * 60 + trackDate.getMinutes()
    if (this.hasTimelineScrubberTarget) {
      this.timelineScrubberTarget.value = startMinute
      this._handleTimelineMinuteChange(startMinute)
    }

    // Start replay and update card button to Pause
    this._startTimelineReplay()
    this._updateTrackReplayButton(true)
  }

  /**
   * Initialize timeline with currently loaded points
   * @private
   */
  async _initializeTimeline() {
    // Ensure points are loaded (fetches with progress badge if needed, no-op if cached)
    await this.mapDataManager.ensurePointsLoaded()

    const points = this._getLoadedPoints()

    if (!points || points.length === 0) {
      Toast.info("No location data loaded for timeline")
      return
    }

    // Create or reset timeline manager
    this.timelineManager = new TimelineManager({
      timezone: this.timezoneValue,
    })

    this.timelineManager.setPoints(points)

    if (!this.timelineManager.hasData()) {
      Toast.info("No location data available for timeline")
      return
    }

    // Update UI
    this._updateTimelineDayDisplay()
    this._updateTimelineDayCount()
    this._updateTimelineDayButtons()
    this._renderTimelineDensity()

    // Initialize replay controls
    this._initializeTimelineReplay()

    // Set scrubber to first point's time or noon
    this._setInitialScrubberPosition()

    // Hide cycle controls initially
    this._hideTimelineCycleControls()
  }

  /**
   * Get loaded points from the data loader
   * @private
   */
  _getLoadedPoints() {
    // Try to get raw points from mapDataManager's last loaded data
    if (this.mapDataManager?.lastLoadedData?.points) {
      return this.mapDataManager.lastLoadedData.points
    }

    // Fallback: try to get from points layer source (GeoJSON format)
    const pointsSource = this.map?.getSource("points-source")
    if (pointsSource?._data?.features) {
      return pointsSource._data.features
    }

    return []
  }

  /**
   * Set initial scrubber position based on first point of the day
   * @private
   */
  _setInitialScrubberPosition() {
    if (!this.hasTimelineScrubberTarget || !this.timelineManager) return

    // Find the first minute with data
    const firstMinute = this.timelineManager.findNearestMinuteWithPoints(0)
    if (firstMinute !== null) {
      this.timelineScrubberTarget.value = firstMinute
      // Trigger the minute change handler to show marker and highlight
      this._handleTimelineMinuteChange(firstMinute)
    } else {
      this.timelineScrubberTarget.value = 720 // Noon
      this._updateTimelineTimeDisplay(720, true)
    }
  }

  /**
   * Handle scrubber hover/drag - triggers marker and map movement
   */
  timelineScrubberHover(event) {
    const minute = parseInt(event.target.value, 10)
    this._handleTimelineMinuteChange(minute)
  }

  /**
   * Handle minute change from scrubber
   * @private
   */
  _handleTimelineMinuteChange(minute) {
    if (!this.timelineManager) return

    // Check if this exact minute has data
    const hasDataAtMinute = this.timelineManager.hasDataAtMinute(minute)

    // Find nearest minute with points
    const nearestMinute =
      this.timelineManager.findNearestMinuteWithPoints(minute)

    // Update time display to show current scrubber position
    this._updateTimelineTimeDisplay(minute, !hasDataAtMinute)

    if (nearestMinute === null) {
      this._clearTimelineMarker()
      this._clearTimelineRouteHighlight()
      this._hideTimelineCycleControls()
      this._updateTimelineSpeedDisplay(null)
      return
    }

    // Reset cycle index when moving to a new minute
    if (!hasDataAtMinute || nearestMinute !== minute) {
      this.timelineManager.resetCycle()
    }

    // Get point at nearest minute
    const point = this.timelineManager.getPointAtPosition(nearestMinute)
    if (!point) return

    // Show marker
    this._showTimelineMarker(point)

    // Update speed display
    this._updateTimelineSpeedDisplay(this._getPointVelocity(point))

    // Move map to point (use faster animation during replay)
    this._flyToTimelinePoint(point, this.timelineReplayActive)

    // Highlight route segment
    this._highlightTimelineRouteSegment(point)

    // Update cycle controls (only if at exact minute with data)
    if (hasDataAtMinute) {
      this._updateTimelineCycleControls(minute)
    } else {
      this._hideTimelineCycleControls()
    }

    // If replay is active, jump to the new position and continue
    if (this.timelineReplayActive && this.timelineReplayPoints?.length > 0) {
      this._jumpReplayToMinute(minute)
    }
  }

  /**
   * Jump replay to a specific minute and continue from there
   * @private
   */
  _jumpReplayToMinute(minute) {
    const dayPoints = this.timelineReplayPoints
    if (!dayPoints || dayPoints.length === 0) return

    // Find the point index closest to (or at) the target minute
    let targetIndex = 0
    for (let i = 0; i < dayPoints.length; i++) {
      const timestamp = this.timelineManager._getTimestamp(dayPoints[i])
      const pointTime = this._parseTimelineTimestamp(timestamp)
      if (pointTime) {
        const date = new Date(pointTime)
        const pointMinute = date.getHours() * 60 + date.getMinutes()
        if (pointMinute >= minute) {
          targetIndex = i
          break
        }
        // Keep updating targetIndex for points before the minute
        // so we get the closest point if we reach the end
        targetIndex = i
      }
    }

    // Update replay state
    this.timelineReplayPointIndex = targetIndex

    const currentPoint = dayPoints[targetIndex]
    const nextPoint = dayPoints[targetIndex + 1]

    this.timelineReplayCurrentCoords = currentPoint
      ? this.timelineManager.getCoordinates(currentPoint)
      : null
    this.timelineReplayNextCoords = nextPoint
      ? this.timelineManager.getCoordinates(nextPoint)
      : this.timelineReplayCurrentCoords

    // Reset timing so interpolation starts fresh from this point
    this.timelineReplayLastTime = performance.now()
  }

  /**
   * Navigate to previous day
   */
  timelinePrevDay() {
    if (!this.timelineManager) return

    // Stop replay when manually changing days
    this._stopTimelineReplay()

    if (this.timelineManager.prevDay()) {
      this._updateTimelineDayDisplay()
      this._updateTimelineDayCount()
      this._updateTimelineDayButtons()
      this._renderTimelineDensity()
      this._setInitialScrubberPosition()
      this._clearTimelineMarker()
      this._clearTimelineRouteHighlight()
      this._hideTimelineCycleControls()
    }
  }

  /**
   * Navigate to next day
   */
  timelineNextDay() {
    if (!this.timelineManager) return

    // Stop replay when manually changing days
    this._stopTimelineReplay()

    if (this.timelineManager.nextDay()) {
      this._updateTimelineDayDisplay()
      this._updateTimelineDayCount()
      this._updateTimelineDayButtons()
      this._renderTimelineDensity()
      this._setInitialScrubberPosition()
      this._clearTimelineMarker()
      this._clearTimelineRouteHighlight()
      this._hideTimelineCycleControls()
    }
  }

  /**
   * Cycle to previous point at current minute
   */
  timelineCyclePrev() {
    if (!this.timelineManager || !this.hasTimelineScrubberTarget) return

    const minute = parseInt(this.timelineScrubberTarget.value, 10)
    this.timelineManager.cyclePrev()

    const point = this.timelineManager.getPointAtPosition(minute)
    if (point) {
      this._showTimelineMarker(point)
      this._updateTimelineSpeedDisplay(this._getPointVelocity(point))
      this._flyToTimelinePoint(point)
      this._highlightTimelineRouteSegment(point)
      this._updateTimelineCycleControls(minute)
    }
  }

  /**
   * Cycle to next point at current minute
   */
  timelineCycleNext() {
    if (!this.timelineManager || !this.hasTimelineScrubberTarget) return

    const minute = parseInt(this.timelineScrubberTarget.value, 10)
    this.timelineManager.cycleNext(minute)

    const point = this.timelineManager.getPointAtPosition(minute)
    if (point) {
      this._showTimelineMarker(point)
      this._updateTimelineSpeedDisplay(this._getPointVelocity(point))
      this._flyToTimelinePoint(point)
      this._highlightTimelineRouteSegment(point)
      this._updateTimelineCycleControls(minute)
    }
  }

  /**
   * Update day display text
   * @private
   */
  _updateTimelineDayDisplay() {
    if (!this.hasTimelineDayDisplayTarget || !this.timelineManager) return
    this.timelineDayDisplayTarget.textContent =
      this.timelineManager.getCurrentDayDisplay()
  }

  /**
   * Update day navigation button states
   * @private
   */
  _updateTimelineDayButtons() {
    if (!this.timelineManager) return

    if (this.hasTimelinePrevDayButtonTarget) {
      this.timelinePrevDayButtonTarget.disabled =
        !this.timelineManager.canGoPrev()
    }

    if (this.hasTimelineNextDayButtonTarget) {
      this.timelineNextDayButtonTarget.disabled =
        !this.timelineManager.canGoNext()
    }
  }

  /**
   * Update time display
   * @private
   * @param {number} minute - Minute of day
   * @param {boolean} showNoData - Whether to show "No data" indicator
   */
  _updateTimelineTimeDisplay(minute, showNoData = false) {
    if (this.hasTimelineTimeDisplayTarget) {
      this.timelineTimeDisplayTarget.textContent =
        TimelineManager.formatMinuteToTime(minute)
    }

    // Show/hide data indicator
    if (this.hasTimelineDataIndicatorTarget) {
      if (showNoData) {
        this.timelineDataIndicatorTarget.classList.remove("hidden")
        this.timelineDataIndicatorTarget.textContent = "No data at this time"
      } else {
        this.timelineDataIndicatorTarget.classList.add("hidden")
      }
    }
  }

  /**
   * Get velocity from point object (handles GeoJSON and raw formats)
   * @private
   * @param {Object} point - Point object (GeoJSON or raw)
   * @returns {string|null} Velocity value or null
   */
  _getPointVelocity(point) {
    if (!point) return null
    // GeoJSON format
    if (point.properties?.velocity !== undefined) {
      return point.properties.velocity
    }
    // Raw format
    if (point.velocity !== undefined) {
      return point.velocity
    }
    return null
  }

  /**
   * Update speed display based on point velocity
   * @private
   * @param {string|number|null} velocity - Velocity value in m/s (from API)
   */
  _updateTimelineSpeedDisplay(velocity) {
    if (!this.hasTimelineSpeedDisplayTarget) return

    const distanceUnit = this.settings?.distance_unit || "km"
    const unit = distanceUnit === "mi" ? "mph" : "km/h"

    if (velocity !== null && velocity !== undefined && velocity !== "") {
      const speedMs = parseFloat(velocity)
      if (!Number.isNaN(speedMs) && speedMs > 0) {
        // Convert m/s to km/h (multiply by 3.6)
        const speedKmh = speedMs * 3.6
        // Convert km/h to mph if needed (multiply by 0.621371)
        const displaySpeed =
          distanceUnit === "mi" ? speedKmh * 0.621371 : speedKmh
        this.timelineSpeedDisplayTarget.textContent = `${Math.round(displaySpeed)} ${unit}`
      } else {
        this.timelineSpeedDisplayTarget.textContent = `?? ${unit}`
      }
    } else {
      this.timelineSpeedDisplayTarget.textContent = `?? ${unit}`
    }
  }

  /**
   * Update day count display
   * @private
   */
  _updateTimelineDayCount() {
    if (!this.hasTimelineDayCountTarget || !this.timelineManager) return

    const dayCount = this.timelineManager.getDayCount()
    const currentIndex = this.timelineManager.currentDayIndex + 1
    const pointCount = this.timelineManager.getCurrentDayPointCount()

    this.timelineDayCountTarget.textContent = `Day ${currentIndex} of ${dayCount} • ${pointCount.toLocaleString()} points`
  }

  /**
   * Render data density visualization on scrubber track
   * @private
   */
  _renderTimelineDensity() {
    if (!this.hasTimelineDensityContainerTarget || !this.timelineManager) return

    // Use 48 segments (30-minute chunks)
    const segments = 48
    const density = this.timelineManager.getDataDensity(segments)

    // Clear existing bars using DOM methods
    while (this.timelineDensityContainerTarget.firstChild) {
      this.timelineDensityContainerTarget.removeChild(
        this.timelineDensityContainerTarget.firstChild,
      )
    }

    // Create density bars using DOM methods
    density.forEach((value) => {
      const bar = document.createElement("div")
      bar.className = "timeline-density-bar"

      if (value > 0) {
        bar.classList.add("has-data")
        if (value > 0.5) {
          bar.classList.add("high-density")
        }
      }

      this.timelineDensityContainerTarget.appendChild(bar)
    })
  }

  /**
   * Update cycle controls visibility and count
   * @private
   */
  _updateTimelineCycleControls(minute) {
    if (!this.hasTimelineCycleControlsTarget || !this.timelineManager) return

    const count = this.timelineManager.getPointCountAtMinute(minute)

    if (count > 1) {
      this.timelineCycleControlsTarget.classList.remove("hidden")
      if (this.hasTimelinePointCounterTarget) {
        const currentIndex = (this.timelineManager.cycleIndex % count) + 1
        this.timelinePointCounterTarget.textContent = `Point ${currentIndex} of ${count}`
      }
    } else {
      this.timelineCycleControlsTarget.classList.add("hidden")
    }
  }

  /**
   * Hide cycle controls
   * @private
   */
  _hideTimelineCycleControls() {
    if (this.hasTimelineCycleControlsTarget) {
      this.timelineCycleControlsTarget.classList.add("hidden")
    }
  }

  // ===== Timeline Replay Methods =====

  /**
   * Toggle replay play/pause
   */
  timelineToggleReplay() {
    if (this.timelineReplayActive) {
      this._stopTimelineReplay()
    } else {
      this._startTimelineReplay()
    }
  }

  /**
   * Handle speed slider change
   */
  timelineSpeedChange(event) {
    const speedIndex = parseInt(event.target.value, 10)
    const speeds = [1, 2, 5, 10]
    this.timelineReplaySpeed = speeds[speedIndex - 1] || 2

    if (this.hasTimelineSpeedLabelTarget) {
      this.timelineSpeedLabelTarget.textContent = `${this.timelineReplaySpeed}x`
    }
  }

  /**
   * Start replay animation
   * @private
   */
  _startTimelineReplay() {
    if (this.timelineReplayActive) return
    if (!this.timelineManager || !this.hasTimelineScrubberTarget) return

    // Get points for current day
    const currentDay = this.timelineManager.getCurrentDay()
    if (!currentDay) return

    const dayPoints = this.timelineManager.pointsByDay[currentDay]
    if (!dayPoints || dayPoints.length === 0) return

    this.timelineReplayActive = true
    this.timelineReplaySpeed = this.timelineReplaySpeed || 2
    this.timelineReplayPoints = dayPoints
    this.timelineReplayPointIndex = 0

    // Find starting index based on current scrubber position
    const currentMinute = parseInt(this.timelineScrubberTarget.value, 10)
    for (let i = 0; i < dayPoints.length; i++) {
      const timestamp = this.timelineManager._getTimestamp(dayPoints[i])
      const pointTime = this._parseTimelineTimestamp(timestamp)
      if (pointTime) {
        const date = new Date(pointTime)
        const pointMinute = date.getHours() * 60 + date.getMinutes()
        if (pointMinute >= currentMinute) {
          this.timelineReplayPointIndex = i
          break
        }
      }
    }

    // Initialize interpolation coordinates
    const startPoint = dayPoints[this.timelineReplayPointIndex]
    const nextPoint = dayPoints[this.timelineReplayPointIndex + 1]
    this.timelineReplayCurrentCoords = startPoint
      ? this.timelineManager.getCoordinates(startPoint)
      : null
    this.timelineReplayNextCoords = nextPoint
      ? this.timelineManager.getCoordinates(nextPoint)
      : this.timelineReplayCurrentCoords

    // Show marker at starting point immediately
    if (startPoint) {
      this._showTimelineMarker(startPoint)
      this._flyToTimelinePoint(startPoint, true)
      this._highlightTimelineRouteSegment(startPoint)
    }

    // Update UI
    if (this.hasTimelinePlayButtonTarget) {
      this.timelinePlayButtonTarget.classList.add("playing")
    }
    if (this.hasTimelinePlayIconTarget) {
      this.timelinePlayIconTarget.classList.add("hidden")
    }
    if (this.hasTimelinePauseIconTarget) {
      this.timelinePauseIconTarget.classList.remove("hidden")
    }

    this.timelineReplayLastTime = performance.now()

    // Start animation loop
    this._timelineReplayFrame()
  }

  /**
   * Stop replay animation
   * @private
   */
  _stopTimelineReplay() {
    // Guard against early calls before initialization
    if (this.timelineReplayActive === undefined) return

    this.timelineReplayActive = false

    // Cancel animation frame
    if (this.timelineReplayAnimationId) {
      cancelAnimationFrame(this.timelineReplayAnimationId)
      this.timelineReplayAnimationId = null
    }

    // Update UI
    if (this.hasTimelinePlayButtonTarget) {
      this.timelinePlayButtonTarget.classList.remove("playing")
    }
    if (this.hasTimelinePlayIconTarget) {
      this.timelinePlayIconTarget.classList.remove("hidden")
    }
    if (this.hasTimelinePauseIconTarget) {
      this.timelinePauseIconTarget.classList.add("hidden")
    }

    // Also reset the track card replay button
    this._updateTrackReplayButton(false)
  }

  /**
   * Update the Replay/Pause button in the track info card
   * @param {boolean} playing - Whether replay is active
   * @private
   */
  _updateTrackReplayButton(playing) {
    const playIcon = document.getElementById("track-replay-play-icon")
    const pauseIcon = document.getElementById("track-replay-pause-icon")
    const label = document.getElementById("track-replay-label")
    if (!playIcon || !pauseIcon || !label) return

    if (playing) {
      playIcon.classList.add("hidden")
      pauseIcon.classList.remove("hidden")
      label.textContent = "Pause"
    } else {
      playIcon.classList.remove("hidden")
      pauseIcon.classList.add("hidden")
      label.textContent = "Replay"
    }
  }

  /**
   * Replay animation frame - iterates over points with smooth interpolation
   * @private
   */
  _timelineReplayFrame() {
    if (!this.timelineReplayActive) return

    const now = performance.now()
    const elapsed = now - this.timelineReplayLastTime

    // Calculate interval between points based on speed
    // Speed 1x = 1 point per 500ms, Speed 10x = 1 point per 50ms
    const intervalMs = 500 / this.timelineReplaySpeed

    // Calculate interpolation progress (0 to 1) - use linear for smooth constant speed
    const progress = Math.min(elapsed / intervalMs, 1)

    // Interpolate marker position between current and next point
    let currentLon, currentLat
    if (this.timelineReplayCurrentCoords && this.timelineReplayNextCoords) {
      currentLon =
        this.timelineReplayCurrentCoords.lon +
        (this.timelineReplayNextCoords.lon -
          this.timelineReplayCurrentCoords.lon) *
          progress
      currentLat =
        this.timelineReplayCurrentCoords.lat +
        (this.timelineReplayNextCoords.lat -
          this.timelineReplayCurrentCoords.lat) *
          progress

      // Update marker position smoothly
      this._showTimelineMarkerAt(currentLon, currentLat)

      // Smoothly pan map to keep marker visible (check every frame for smoothness)
      this._panMapToFollowMarker(currentLon, currentLat)
    }

    // When interval is complete, move to next point
    if (elapsed >= intervalMs) {
      this.timelineReplayLastTime = now

      // Move to next point
      this.timelineReplayPointIndex++

      // Check if we've reached the end of points for this day
      if (this.timelineReplayPointIndex >= this.timelineReplayPoints.length) {
        // Try to go to next day
        if (this.timelineManager.canGoNext()) {
          this.timelineManager.nextDay()
          this._updateTimelineDayDisplay()
          this._updateTimelineDayCount()
          this._updateTimelineDayButtons()
          this._renderTimelineDensity()

          // Get points for new day
          const newDay = this.timelineManager.getCurrentDay()
          this.timelineReplayPoints =
            this.timelineManager.pointsByDay[newDay] || []
          this.timelineReplayPointIndex = 0

          if (this.timelineReplayPoints.length === 0) {
            this._stopTimelineReplay()
            return
          }
        } else {
          // End of data, stop replay
          this._stopTimelineReplay()
          return
        }
      }

      // Get current and next points for interpolation
      const currentPoint =
        this.timelineReplayPoints[this.timelineReplayPointIndex]
      const nextPoint =
        this.timelineReplayPoints[this.timelineReplayPointIndex + 1]

      if (!currentPoint) {
        this._stopTimelineReplay()
        return
      }

      // Store coordinates for interpolation
      this.timelineReplayCurrentCoords =
        this.timelineManager.getCoordinates(currentPoint)
      this.timelineReplayNextCoords = nextPoint
        ? this.timelineManager.getCoordinates(nextPoint)
        : this.timelineReplayCurrentCoords

      // Update speed display for current point
      this._updateTimelineSpeedDisplay(this._getPointVelocity(currentPoint))

      // Get minute for this point to update scrubber
      const timestamp = this.timelineManager._getTimestamp(currentPoint)
      const pointTime = this._parseTimelineTimestamp(timestamp)
      if (pointTime) {
        const date = new Date(pointTime)
        const minute = date.getHours() * 60 + date.getMinutes()

        // Update scrubber position
        this.timelineScrubberTarget.value = minute

        // Update time display
        this._updateTimelineTimeDisplay(minute, false)
      }

      // Highlight route segment (less frequently to reduce overhead)
      if (this.timelineReplayPointIndex % 5 === 0) {
        this._highlightTimelineRouteSegment(currentPoint)
      }

      // Hide cycle controls during replay
      this._hideTimelineCycleControls()
    }

    // Continue animation
    this.timelineReplayAnimationId = requestAnimationFrame(() =>
      this._timelineReplayFrame(),
    )
  }

  /**
   * Smoothly pan map to keep marker visible during replay
   * Only pans when marker is near the edge of the viewport
   * @private
   */
  _panMapToFollowMarker(lon, lat) {
    if (!this.map) return

    // Get current map bounds
    const bounds = this.map.getBounds()
    const center = this.map.getCenter()

    // Calculate how far the marker is from the edges (as a percentage of viewport)
    const lngSpan = bounds.getEast() - bounds.getWest()
    const latSpan = bounds.getNorth() - bounds.getSouth()

    // Calculate distance from center as percentage of viewport
    const lngOffset = (lon - center.lng) / lngSpan
    const latOffset = (lat - center.lat) / latSpan

    // If marker is more than 30% from center, reposition immediately
    const threshold = 0.3
    if (Math.abs(lngOffset) > threshold || Math.abs(latOffset) > threshold) {
      this.map.setCenter([lon, lat])
    }
  }

  /**
   * Show timeline marker at specific coordinates (for interpolation)
   * @private
   */
  _showTimelineMarkerAt(lon, lat) {
    if (lon === undefined || lat === undefined) return

    const timelineMarkerLayer = this.layerManager?.getLayer("timelineMarker")
    if (timelineMarkerLayer) {
      timelineMarkerLayer.showMarker(lon, lat)
    }
  }

  /**
   * Initialize replay state
   * @private
   */
  _initializeTimelineReplay() {
    this.timelineReplayActive = false
    this.timelineReplaySpeed = 2
    this.timelineReplayPoints = []
    this.timelineReplayPointIndex = 0
    this.timelineReplayLastTime = 0
    this.timelineReplayAnimationId = null
    this.timelineReplayCurrentCoords = null
    this.timelineReplayNextCoords = null
    // Set initial speed label
    if (this.hasTimelineSpeedLabelTarget) {
      this.timelineSpeedLabelTarget.textContent = "2x"
    }
    if (this.hasTimelineSpeedSliderTarget) {
      this.timelineSpeedSliderTarget.value = 2
    }
  }

  /**
   * Show timeline marker at point location
   * @private
   */
  _showTimelineMarker(point) {
    const coords = this.timelineManager?.getCoordinates(point)
    if (!coords) return

    const timelineMarkerLayer = this.layerManager?.getLayer("timelineMarker")
    if (timelineMarkerLayer) {
      timelineMarkerLayer.showMarker(coords.lon, coords.lat, {
        timestamp: this.timelineManager._getTimestamp(point),
      })
    }
  }

  /**
   * Clear timeline marker
   * @private
   */
  _clearTimelineMarker() {
    const timelineMarkerLayer = this.layerManager?.getLayer("timelineMarker")
    if (timelineMarkerLayer) {
      timelineMarkerLayer.clear()
    }
  }

  /**
   * Fly map to timeline point
   * @private
   * @param {Object} point - Point object
   * @param {boolean} fast - Use faster animation (for replay)
   */
  _flyToTimelinePoint(point, fast = false) {
    const coords = this.timelineManager?.getCoordinates(point)
    if (!coords || !this.map) return

    this.map.flyTo({
      center: [coords.lon, coords.lat],
      zoom: Math.max(this.map.getZoom(), 14),
      duration: fast ? 100 : 500,
    })
  }

  /**
   * Highlight route segment containing the timeline point
   * @private
   */
  _highlightTimelineRouteSegment(point) {
    const routesLayer = this.layerManager?.getLayer("routes")
    if (!routesLayer) return

    const coords = this.timelineManager?.getCoordinates(point)
    if (!coords) return

    // Query the routes source to find feature containing this point
    const routesSource = this.map?.getSource("routes-source")
    if (!routesSource?._data?.features) {
      routesLayer.setHoverRoute(null)
      return
    }

    const timestamp = this.timelineManager._getTimestamp(point)
    if (!timestamp) {
      routesLayer.setHoverRoute(null)
      return
    }

    // Parse timestamp consistently (handle both Unix seconds and milliseconds)
    const pointTime = this._parseTimelineTimestamp(timestamp)

    // Find the route segment containing this timestamp
    const matchingFeature = routesSource._data.features.find((feature) => {
      const startTime = feature.properties?.startTime
      const endTime = feature.properties?.endTime

      if (startTime && endTime) {
        const start = this._parseTimelineTimestamp(startTime)
        const end = this._parseTimelineTimestamp(endTime)
        return pointTime >= start && pointTime <= end
      }
      return false
    })

    if (matchingFeature) {
      routesLayer.setHoverRoute(matchingFeature)
    } else {
      routesLayer.setHoverRoute(null)
    }
  }

  /**
   * Parse timestamp to milliseconds, handling various formats
   * @private
   */
  _parseTimelineTimestamp(timestamp) {
    if (!timestamp) return 0

    // Handle ISO 8601 string
    if (typeof timestamp === "string") {
      return new Date(timestamp).getTime()
    }

    // Handle Unix timestamp
    if (typeof timestamp === "number") {
      // Unix timestamp in seconds (< year 2286 in seconds)
      if (timestamp < 10000000000) {
        return timestamp * 1000
      }
      // Unix timestamp in milliseconds
      return timestamp
    }

    return 0
  }

  /**
   * Clear timeline route highlight
   * @private
   */
  _clearTimelineRouteHighlight() {
    const routesLayer = this.layerManager?.getLayer("routes")
    if (routesLayer) {
      routesLayer.setHoverRoute(null)
    }
  }
}
