import { Controller } from "@hotwired/stimulus"
import { Toast } from "maps_maplibre/components/toast"
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
    "loading",
    "loadingText",
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
  ]

  async connect() {
    this.cleanup = new CleanupHelper()

    // Initialize API and settings
    SettingsManager.initialize(this.apiKeyValue)
    this.settingsController = new SettingsController(this)
    await this.settingsController.loadSettings()
    this.settings = this.settingsController.settings
    this.settings.timezone = this.timezoneValue || "UTC"

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

    this.searchManager = new SearchManager(
      this.map,
      this.apiKeyValue,
      this.timezoneValue,
    )
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
      {
        ...options,
        onProgress: this.updateLoadingProgress.bind(this),
      },
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
   * Show loading indicator
   */
  showLoading() {
    this.loadingTarget.classList.remove("hidden")
  }

  /**
   * Hide loading indicator
   */
  hideLoading() {
    this.loadingTarget.classList.add("hidden")
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
}
