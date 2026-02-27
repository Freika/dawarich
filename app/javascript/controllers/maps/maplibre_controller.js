import { Controller } from "@hotwired/stimulus"
import { Toast } from "maps_maplibre/components/toast"
import { ReplayManager } from "maps_maplibre/managers/replay_manager"
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
    // Replay
    "replayPanel",
    "replayScrubber",
    "replayScrubberTrack",
    "replayDensityContainer",
    "replayDayDisplay",
    "replayDayCount",
    "replayTimeDisplay",
    "replayDataIndicator",
    "replayCycleControls",
    "replayPointCounter",
    "replayPrevDayButton",
    "replayNextDayButton",
    // Timeline feed
    "timelineFeedContainer",
    // Replay playback
    "replayPlayButton",
    "replayPlayIcon",
    "replayPauseIcon",
    "replaySpeedSlider",
    "replaySpeedLabel",
    // Replay speed display (velocity)
    "replaySpeedDisplay",
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
    this.settings.timezone = this.timezoneValue

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

    // Listen for tab changes to trigger timeline feed loading via Turbo Frame
    this.boundHandleTabChanged = this.handleTabChanged.bind(this)
    this.cleanup.addEventListener(
      document,
      "map-panel:tab-changed",
      this.boundHandleTabChanged,
    )

    // Listen for day-expanded/collapsed events from the timeline-feed Stimulus controller
    this.boundHandleDayExpanded = this.handleDayExpanded.bind(this)
    this.cleanup.addEventListener(
      document,
      "timeline-feed:day-expanded",
      this.boundHandleDayExpanded,
    )
    this.boundHandleDayCollapsed = this.handleDayCollapsed.bind(this)
    this.cleanup.addEventListener(
      document,
      "timeline-feed:day-collapsed",
      this.boundHandleDayCollapsed,
    )

    // Listen for entry hover/unhover events from the timeline-feed controller
    this.boundHandleEntryHover = this.handleEntryHover.bind(this)
    this.cleanup.addEventListener(
      document,
      "timeline-feed:entry-hover",
      this.boundHandleEntryHover,
    )
    this.boundHandleEntryUnhover = this.handleEntryUnhover.bind(this)
    this.cleanup.addEventListener(
      document,
      "timeline-feed:entry-unhover",
      this.boundHandleEntryUnhover,
    )

    // Listen for entry click/deselect events from the timeline-feed controller
    this.boundHandleEntryClick = this.handleEntryClick.bind(this)
    this.cleanup.addEventListener(
      document,
      "timeline-feed:entry-click",
      this.boundHandleEntryClick,
    )
    this.boundHandleEntryDeselect = this.handleEntryDeselect.bind(this)
    this.cleanup.addEventListener(
      document,
      "timeline-feed:entry-deselect",
      this.boundHandleEntryDeselect,
    )

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

    this.loadMapData().then(() => {
      if (this.settings?.familyEnabled) {
        this.loadFamilyMembers()
      }
    })

    // Show family members list immediately (doesn't depend on layer)
    if (this.settings?.familyEnabled && this.hasFamilyMembersListTarget) {
      this.familyMembersListTarget.style.display = "block"
    }
  }

  disconnect() {
    this._stopReplayPlayback()
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

    this._clearDayHighlight()
    this.loadMapData()
    this.refreshTimelineFeedIfActive()
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
      parts.push(`${familyCount.toLocaleString()} family members`)
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

  /**
   * Handle tab change events from the map panel controller
   */
  handleTabChanged(event) {
    const { tab } = event.detail
    if (tab === "timeline-feed") {
      this.loadTimelineFeed()
    } else if (this._highlightedDay) {
      // Leaving timeline-feed tab — restore full opacity
      this._clearDayHighlight()
    }
  }

  /**
   * Called when the timeline-feed tab becomes active.
   * Sets the Turbo Frame src to trigger server-rendered HTML load.
   */
  loadTimelineFeed() {
    if (!this.hasTimelineFeedContainerTarget) return

    const frame = this.timelineFeedContainerTarget
    const url = `/map/timeline_feeds?start_at=${encodeURIComponent(this.startDateValue)}&end_at=${encodeURIComponent(this.endDateValue)}`

    if (frame.getAttribute("src") !== url) {
      // Show skeleton while loading
      const skeleton = document.getElementById("timeline-feed-skeleton")
      if (skeleton) {
        frame.innerHTML = skeleton.innerHTML
      }
      frame.src = url
    }
  }

  /**
   * Refresh timeline feed if the tab is currently active
   */
  refreshTimelineFeedIfActive() {
    const activeTab = this.element.querySelector(
      '.tab-content.active[data-tab-content="timeline-feed"]',
    )
    if (activeTab && this.hasTimelineFeedContainerTarget) {
      // Force reload by clearing cached src
      this.timelineFeedContainerTarget.removeAttribute("src")
      this.loadTimelineFeed()
    }
  }

  /**
   * Handle day-expanded events from the timeline-feed controller.
   * Fits the map to the day's bounding box and dims non-matching features.
   */
  handleDayExpanded(event) {
    const { bounds, day } = event.detail
    if (!this.map) return

    if (bounds) {
      const { sw_lat, sw_lng, ne_lat, ne_lng } = bounds
      this.map.fitBounds(
        [
          [sw_lng, sw_lat],
          [ne_lng, ne_lat],
        ],
        { padding: 60, maxZoom: 15, duration: 800 },
      )
    }

    if (day) {
      this._applyDayHighlight(day)
      this._showDayVisits(day)
    }
  }

  /**
   * Handle day-collapsed events — restore full opacity on all layers.
   */
  handleDayCollapsed() {
    this._clearDayHighlight()
  }

  /**
   * Dim non-matching features for the selected day.
   * Routes and points use Unix timestamps (seconds);
   * visits use ISO 8601 strings (lexicographically sortable).
   * @param {string} day - Date string "YYYY-MM-DD"
   * @private
   */
  _applyDayHighlight(day) {
    if (!this.map) return

    this._highlightedDay = day
    const DIM = 0.04
    const routeFull = this.settings?.routeOpacity ?? 0.8

    // Compute day boundaries as Unix seconds
    const dayStart = new Date(`${day}T00:00:00`).getTime() / 1000
    const dayEnd = new Date(`${day}T23:59:59`).getTime() / 1000

    // ISO boundaries for visit layers (lexicographic comparison)
    const isoStart = `${day}T00:00:00`
    const isoEnd = `${day}T23:59:59`

    // Routes: startTime is Unix seconds
    const routeExpr = this._dayRangeExpr(
      "startTime",
      dayStart,
      dayEnd,
      routeFull,
      DIM,
    )
    this._safeSetPaint("routes", "line-opacity", routeExpr)
    this._safeSetPaint("routes-base", "line-opacity", routeExpr)

    // Points: timestamp is Unix seconds
    const pointExpr = this._dayRangeExpr("timestamp", dayStart, dayEnd, 1, DIM)
    this._safeSetPaint("points", "circle-opacity", pointExpr)
    this._safeSetPaint("points", "circle-stroke-opacity", pointExpr)

    // Visits: started_at is ISO 8601 string
    const visitExpr = this._dayRangeExpr(
      "started_at",
      isoStart,
      isoEnd,
      0.9,
      DIM,
    )
    this._safeSetPaint("visits", "circle-opacity", visitExpr)
    this._safeSetPaint("visits", "circle-stroke-opacity", visitExpr)

    // Visit labels
    const labelExpr = this._dayRangeExpr("started_at", isoStart, isoEnd, 1, DIM)
    this._safeSetPaint("visits-labels", "text-opacity", labelExpr)

    // Tracks: start_at is ISO 8601 string
    const trackExpr = this._dayRangeExpr("start_at", isoStart, isoEnd, 0.7, DIM)
    this._safeSetPaint("tracks", "line-opacity", trackExpr)
  }

  /**
   * Restore default opacity on all layers.
   * @private
   */
  _clearDayHighlight() {
    if (!this.map) return

    this._highlightedDay = null
    this._hideDayVisits()
    const routeOpacity = this.settings?.routeOpacity ?? 0.8

    this._safeSetPaint("routes", "line-opacity", routeOpacity)
    this._safeSetPaint("routes-base", "line-opacity", routeOpacity)
    this._safeSetPaint("points", "circle-opacity", 1)
    this._safeSetPaint("points", "circle-stroke-opacity", 1)
    this._safeSetPaint("visits", "circle-opacity", 0.9)
    this._safeSetPaint("visits", "circle-stroke-opacity", 1)
    this._safeSetPaint("visits-labels", "text-opacity", 1)
    this._safeSetPaint("tracks", "line-opacity", 0.7)
  }

  /**
   * Handle entry-hover events from the timeline feed.
   * Highlights the matching route/visit on the map by dimming everything else.
   */
  handleEntryHover(event) {
    const { entryType, startedAt, endedAt, trackId } = event.detail
    if (!this.map || !startedAt || !endedAt) return

    this._entryHighlightActive = true

    const DIM = 0.08
    const startUnix = new Date(startedAt).getTime() / 1000
    const endUnix = new Date(endedAt).getTime() / 1000
    const routeFull = this.settings?.routeOpacity ?? 0.8

    // Routes: startTime is Unix seconds
    const routeExpr = this._dayRangeExpr(
      "startTime",
      startUnix,
      endUnix,
      routeFull,
      DIM,
    )
    this._safeSetPaint("routes", "line-opacity", routeExpr)
    this._safeSetPaint("routes-base", "line-opacity", routeExpr)

    // Points: timestamp is Unix seconds
    const pointExpr = this._dayRangeExpr(
      "timestamp",
      startUnix,
      endUnix,
      1,
      DIM,
    )
    this._safeSetPaint("points", "circle-opacity", pointExpr)
    this._safeSetPaint("points", "circle-stroke-opacity", pointExpr)

    // Visits: started_at is ISO 8601 string
    const visitExpr = this._dayRangeExpr(
      "started_at",
      startedAt,
      endedAt,
      0.9,
      DIM,
    )
    this._safeSetPaint("visits", "circle-opacity", visitExpr)
    this._safeSetPaint("visits", "circle-stroke-opacity", visitExpr)

    const labelExpr = this._dayRangeExpr(
      "started_at",
      startedAt,
      endedAt,
      1,
      DIM,
    )
    this._safeSetPaint("visits-labels", "text-opacity", labelExpr)

    // Tracks: start_at is ISO 8601 string
    const trackExpr = this._dayRangeExpr(
      "start_at",
      startedAt,
      endedAt,
      0.7,
      DIM,
    )
    this._safeSetPaint("tracks", "line-opacity", trackExpr)

    // Highlight the matching track with border + animation for journey entries
    if (entryType === "journey") {
      const feature = this._findTrackFeature(trackId, startedAt)
      if (feature) {
        const tracksLayer = this.layerManager.getLayer("tracks")
        if (tracksLayer?.setSelectedTrack) {
          tracksLayer.setSelectedTrack(feature)
          this._hoverHighlightedTrack = true
        }
      }
    }
  }

  /**
   * Handle entry-unhover events — restore to day highlight or default opacity.
   */
  handleEntryUnhover() {
    if (!this.map) return
    this._entryHighlightActive = false

    // Clear track hover highlight unless a track is click-selected
    if (this._hoverHighlightedTrack && !this._timelineSelectedTrack) {
      const tracksLayer = this.layerManager.getLayer("tracks")
      if (tracksLayer?.setSelectedTrack) {
        tracksLayer.setSelectedTrack(null)
      }
      this._hoverHighlightedTrack = false
    }

    if (this._highlightedDay) {
      // Restore day-level highlight
      this._applyDayHighlight(this._highlightedDay)
    } else {
      this._clearDayHighlight()
    }
  }

  /**
   * Handle entry-click events from the timeline feed (journey card opened).
   * Zooms to the track and applies the selection highlight.
   */
  handleEntryClick(event) {
    const { trackId, startedAt } = event.detail
    if (!this.map) return

    const feature = this._findTrackFeature(trackId, startedAt)
    if (!feature) return

    // Zoom to track bounding box
    const coords = feature.geometry?.coordinates
    if (coords?.length > 0) {
      let minLng = Infinity
      let minLat = Infinity
      let maxLng = -Infinity
      let maxLat = -Infinity
      for (const [lng, lat] of coords) {
        if (lng < minLng) minLng = lng
        if (lat < minLat) minLat = lat
        if (lng > maxLng) maxLng = lng
        if (lat > maxLat) maxLat = lat
      }
      this.map.fitBounds(
        [
          [minLng, minLat],
          [maxLng, maxLat],
        ],
        { padding: 60, maxZoom: 15, duration: 800 },
      )
    }

    // Apply track selection highlight
    const tracksLayer = this.layerManager.getLayer("tracks")
    if (tracksLayer?.setSelectedTrack) {
      tracksLayer.setSelectedTrack(feature)
      this._timelineSelectedTrack = true
      this._hoverHighlightedTrack = false
    }
  }

  /**
   * Handle entry-deselect events from the timeline feed (journey card closed).
   * Clears track selection and restores day highlight if active.
   */
  handleEntryDeselect() {
    if (!this.map) return

    const tracksLayer = this.layerManager.getLayer("tracks")
    if (tracksLayer?.setSelectedTrack) {
      tracksLayer.setSelectedTrack(null)
    }
    this._timelineSelectedTrack = false
    this._hoverHighlightedTrack = false

    // Restore day-level highlight or default opacity
    if (this._highlightedDay) {
      this._applyDayHighlight(this._highlightedDay)
    } else {
      this._clearDayHighlight()
    }
  }

  /**
   * Build a MapLibre expression: full opacity if property is within [start, end], dim otherwise.
   * @private
   */
  _dayRangeExpr(property, rangeStart, rangeEnd, fullOpacity, dimOpacity) {
    return [
      "case",
      [
        "all",
        ["has", property],
        [">=", ["get", property], rangeStart],
        ["<=", ["get", property], rangeEnd],
      ],
      fullOpacity,
      dimOpacity,
    ]
  }

  /**
   * Safely set a paint property on a MapLibre layer (no-op if layer doesn't exist).
   * @private
   */
  _safeSetPaint(layerId, property, value) {
    if (this.map.getLayer(layerId)) {
      this.map.setPaintProperty(layerId, property, value)
    }
  }

  /**
   * Show visit markers for the given day, even if the Visits layer is globally disabled.
   * @param {string} day - Date string "YYYY-MM-DD"
   * @private
   */
  async _showDayVisits(day) {
    const visitsLayer = this.layerManager?.getLayer("visits")
    if (!visitsLayer) return

    const wasHidden = !visitsLayer.visible

    // Only override if the layer is currently hidden
    if (!wasHidden) return

    // Get visits for this day
    let dayVisits = []
    if (this.filterManager?.allVisits?.length > 0) {
      dayVisits = this.filterManager.allVisits.filter((v) => {
        const visitDay = v.started_at?.substring(0, 10)
        return visitDay === day
      })
    } else {
      try {
        dayVisits = await this.api.fetchVisits({
          start_at: `${day}T00:00:00`,
          end_at: `${day}T23:59:59`,
        })
      } catch {
        return
      }
    }

    if (dayVisits.length === 0) return

    // Store override state for restoration
    const source = this.map.getSource(visitsLayer.sourceId)
    this._visitsOverride = {
      wasHidden,
      previousData: source?._data || {
        type: "FeatureCollection",
        features: [],
      },
    }

    // Update the visits source with the day's visits and show the layer
    const geoJSON = this.dataLoader.visitsToGeoJSON(dayVisits)
    visitsLayer.update(geoJSON)
    visitsLayer.show()
  }

  /**
   * Restore the visits layer to its previous state after day collapse.
   * @private
   */
  _hideDayVisits() {
    if (!this._visitsOverride) return

    const visitsLayer = this.layerManager?.getLayer("visits")
    if (!visitsLayer) {
      this._visitsOverride = null
      return
    }

    if (this._visitsOverride.wasHidden) {
      visitsLayer.update(this._visitsOverride.previousData)
      visitsLayer.hide()
    }

    this._visitsOverride = null
  }

  /**
   * Find a track feature from the tracks source by ID or start time.
   * @param {string} trackId - Track ID (primary match)
   * @param {string} startedAt - ISO start time (fallback match)
   * @returns {Object|null} GeoJSON feature or null
   * @private
   */
  _findTrackFeature(trackId, startedAt) {
    const tracksLayer = this.layerManager?.getLayer("tracks")
    if (!tracksLayer) return null

    const source = this.map.getSource(tracksLayer.sourceId)
    const sourceData = source?._data || tracksLayer.data
    if (!sourceData?.features) return null

    // Primary: match by track ID
    if (trackId) {
      const byId = sourceData.features.find(
        (f) => String(f.properties?.id) === String(trackId),
      )
      if (byId) return byId
    }

    // Fallback: match by start_at time
    if (startedAt) {
      return (
        sourceData.features.find((f) => f.properties?.start_at === startedAt) ||
        null
      )
    }

    return null
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

      const response = await fetch("/api/v1/families/locations", {
        headers: {
          Accept: "application/json",
          "Content-Type": "application/json",
          Authorization: `Bearer ${this.apiKeyValue}`,
        },
      })

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

  // ===== Replay Methods =====

  /**
   * Toggle replay panel visibility
   */
  async toggleReplay() {
    if (!this.hasReplayPanelTarget) return

    const isVisible = !this.replayPanelTarget.classList.contains("hidden")

    if (isVisible) {
      // Hide replay
      this._stopReplayPlayback()
      this.replayPanelTarget.classList.add("hidden")
      this._clearReplayMarker()
      this._clearReplayRouteHighlight()
      this._updateReplaySpeedDisplay(null)
    } else {
      // Show replay and initialize with loaded points
      await this._initializeReplay()
      this.replayPanelTarget.classList.remove("hidden")
    }
  }

  /**
   * Replay a specific track from its start time (triggered from track info card)
   */
  async replayTrack(event) {
    if (!this.hasReplayPanelTarget) return

    // If replay is already active, pause it
    if (this.replayActive) {
      this._stopReplayPlayback()
      return
    }

    // If replay is already visible and initialized, resume from current position
    const isVisible = !this.replayPanelTarget.classList.contains("hidden")
    if (isVisible && this.replayManager?.hasData()) {
      this._startReplayPlayback()
      this._updateTrackReplayButton(true)
      return
    }

    const trackStart = event.currentTarget.dataset.trackStart
    if (!trackStart) return

    const trackDate = new Date(trackStart)
    if (Number.isNaN(trackDate.getTime())) return

    // First time: initialize replay and navigate to the track's day
    await this._initializeReplay()
    this.replayPanelTarget.classList.remove("hidden")

    if (!this.replayManager?.hasData()) return

    // Navigate to the day matching the track's start
    const targetDay = `${trackDate.getFullYear()}-${String(trackDate.getMonth() + 1).padStart(2, "0")}-${String(trackDate.getDate()).padStart(2, "0")}`
    const dayIndex = this.replayManager.availableDays.indexOf(targetDay)

    if (dayIndex >= 0 && dayIndex !== this.replayManager.currentDayIndex) {
      this.replayManager.currentDayIndex = dayIndex
      this.replayManager.buildMinuteIndex()
      this._updateReplayDayDisplay()
      this._updateReplayDayCount()
      this._updateReplayDayButtons()
      this._renderReplayDensity()
    }

    // Set scrubber to the track's start minute
    const startMinute = trackDate.getHours() * 60 + trackDate.getMinutes()
    if (this.hasReplayScrubberTarget) {
      this.replayScrubberTarget.value = startMinute
      this._handleReplayMinuteChange(startMinute)
    }

    // Start replay and update card button to Pause
    this._startReplayPlayback()
    this._updateTrackReplayButton(true)
  }

  /**
   * Initialize replay with currently loaded points
   * @private
   */
  async _initializeReplay() {
    // Ensure points are loaded (fetches with progress badge if needed, no-op if cached)
    await this.mapDataManager.ensurePointsLoaded()

    const points = this._getLoadedPoints()

    if (!points || points.length === 0) {
      Toast.info("No location data loaded for replay")
      return
    }

    // Create or reset replay manager
    this.replayManager = new ReplayManager({
      timezone: this.timezoneValue,
    })

    this.replayManager.setPoints(points)

    if (!this.replayManager.hasData()) {
      Toast.info("No location data available for replay")
      return
    }

    // Update UI
    this._updateReplayDayDisplay()
    this._updateReplayDayCount()
    this._updateReplayDayButtons()
    this._renderReplayDensity()

    // Initialize replay controls
    this._initializeReplayState()

    // Set scrubber to first point's time or noon
    this._setInitialScrubberPosition()

    // Hide cycle controls initially
    this._hideReplayCycleControls()
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
    if (!this.hasReplayScrubberTarget || !this.replayManager) return

    // Find the first minute with data
    const firstMinute = this.replayManager.findNearestMinuteWithPoints(0)
    if (firstMinute !== null) {
      this.replayScrubberTarget.value = firstMinute
      // Trigger the minute change handler to show marker and highlight
      this._handleReplayMinuteChange(firstMinute)
    } else {
      this.replayScrubberTarget.value = 720 // Noon
      this._updateReplayTimeDisplay(720, true)
    }
  }

  /**
   * Handle scrubber hover/drag - triggers marker and map movement
   */
  replayScrubberHover(event) {
    const minute = parseInt(event.target.value, 10)
    this._handleReplayMinuteChange(minute)
  }

  /**
   * Handle minute change from scrubber
   * @private
   */
  _handleReplayMinuteChange(minute) {
    if (!this.replayManager) return

    // Check if this exact minute has data
    const hasDataAtMinute = this.replayManager.hasDataAtMinute(minute)

    // Find nearest minute with points
    const nearestMinute = this.replayManager.findNearestMinuteWithPoints(minute)

    // Update time display to show current scrubber position
    this._updateReplayTimeDisplay(minute, !hasDataAtMinute)

    if (nearestMinute === null) {
      this._clearReplayMarker()
      this._clearReplayRouteHighlight()
      this._hideReplayCycleControls()
      this._updateReplaySpeedDisplay(null)
      return
    }

    // Reset cycle index when moving to a new minute
    if (!hasDataAtMinute || nearestMinute !== minute) {
      this.replayManager.resetCycle()
    }

    // Get point at nearest minute
    const point = this.replayManager.getPointAtPosition(nearestMinute)
    if (!point) return

    // Show marker
    this._showReplayMarker(point)

    // Update speed display
    this._updateReplaySpeedDisplay(this._getPointVelocity(point))

    // Move map to point (use faster animation during replay)
    this._flyToReplayPoint(point, this.replayActive)

    // Highlight route segment
    this._highlightReplayRouteSegment(point)

    // Update cycle controls (only if at exact minute with data)
    if (hasDataAtMinute) {
      this._updateReplayCycleControls(minute)
    } else {
      this._hideReplayCycleControls()
    }

    // If replay is active, jump to the new position and continue
    if (this.replayActive && this.replayPoints?.length > 0) {
      this._jumpReplayToMinute(minute)
    }
  }

  /**
   * Jump replay to a specific minute and continue from there
   * @private
   */
  _jumpReplayToMinute(minute) {
    const dayPoints = this.replayPoints
    if (!dayPoints || dayPoints.length === 0) return

    // Find the point index closest to (or at) the target minute
    let targetIndex = 0
    for (let i = 0; i < dayPoints.length; i++) {
      const timestamp = this.replayManager._getTimestamp(dayPoints[i])
      const pointTime = this._parseReplayTimestamp(timestamp)
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
    this.replayPointIndex = targetIndex

    const currentPoint = dayPoints[targetIndex]
    const nextPoint = dayPoints[targetIndex + 1]

    this.replayCurrentCoords = currentPoint
      ? this.replayManager.getCoordinates(currentPoint)
      : null
    this.replayNextCoords = nextPoint
      ? this.replayManager.getCoordinates(nextPoint)
      : this.replayCurrentCoords

    // Reset timing so interpolation starts fresh from this point
    this.replayLastTime = performance.now()
  }

  /**
   * Navigate to previous day
   */
  replayPrevDay() {
    if (!this.replayManager) return

    // Stop replay when manually changing days
    this._stopReplayPlayback()

    if (this.replayManager.prevDay()) {
      this._updateReplayDayDisplay()
      this._updateReplayDayCount()
      this._updateReplayDayButtons()
      this._renderReplayDensity()
      this._setInitialScrubberPosition()
      this._clearReplayMarker()
      this._clearReplayRouteHighlight()
      this._hideReplayCycleControls()
    }
  }

  /**
   * Navigate to next day
   */
  replayNextDay() {
    if (!this.replayManager) return

    // Stop replay when manually changing days
    this._stopReplayPlayback()

    if (this.replayManager.nextDay()) {
      this._updateReplayDayDisplay()
      this._updateReplayDayCount()
      this._updateReplayDayButtons()
      this._renderReplayDensity()
      this._setInitialScrubberPosition()
      this._clearReplayMarker()
      this._clearReplayRouteHighlight()
      this._hideReplayCycleControls()
    }
  }

  /**
   * Cycle to previous point at current minute
   */
  replayCyclePrev() {
    if (!this.replayManager || !this.hasReplayScrubberTarget) return

    const minute = parseInt(this.replayScrubberTarget.value, 10)
    this.replayManager.cyclePrev()

    const point = this.replayManager.getPointAtPosition(minute)
    if (point) {
      this._showReplayMarker(point)
      this._updateReplaySpeedDisplay(this._getPointVelocity(point))
      this._flyToReplayPoint(point)
      this._highlightReplayRouteSegment(point)
      this._updateReplayCycleControls(minute)
    }
  }

  /**
   * Cycle to next point at current minute
   */
  replayCycleNext() {
    if (!this.replayManager || !this.hasReplayScrubberTarget) return

    const minute = parseInt(this.replayScrubberTarget.value, 10)
    this.replayManager.cycleNext(minute)

    const point = this.replayManager.getPointAtPosition(minute)
    if (point) {
      this._showReplayMarker(point)
      this._updateReplaySpeedDisplay(this._getPointVelocity(point))
      this._flyToReplayPoint(point)
      this._highlightReplayRouteSegment(point)
      this._updateReplayCycleControls(minute)
    }
  }

  /**
   * Update day display text
   * @private
   */
  _updateReplayDayDisplay() {
    if (!this.hasReplayDayDisplayTarget || !this.replayManager) return
    this.replayDayDisplayTarget.textContent =
      this.replayManager.getCurrentDayDisplay()
  }

  /**
   * Update day navigation button states
   * @private
   */
  _updateReplayDayButtons() {
    if (!this.replayManager) return

    if (this.hasReplayPrevDayButtonTarget) {
      this.replayPrevDayButtonTarget.disabled = !this.replayManager.canGoPrev()
    }

    if (this.hasReplayNextDayButtonTarget) {
      this.replayNextDayButtonTarget.disabled = !this.replayManager.canGoNext()
    }
  }

  /**
   * Update time display
   * @private
   * @param {number} minute - Minute of day
   * @param {boolean} showNoData - Whether to show "No data" indicator
   */
  _updateReplayTimeDisplay(minute, showNoData = false) {
    if (this.hasReplayTimeDisplayTarget) {
      this.replayTimeDisplayTarget.textContent =
        ReplayManager.formatMinuteToTime(minute)
    }

    // Show/hide data indicator
    if (this.hasReplayDataIndicatorTarget) {
      if (showNoData) {
        this.replayDataIndicatorTarget.classList.remove("hidden")
        this.replayDataIndicatorTarget.textContent = "No data at this time"
      } else {
        this.replayDataIndicatorTarget.classList.add("hidden")
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
  _updateReplaySpeedDisplay(velocity) {
    if (!this.hasReplaySpeedDisplayTarget) return

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
        this.replaySpeedDisplayTarget.textContent = `${Math.round(displaySpeed)} ${unit}`
      } else {
        this.replaySpeedDisplayTarget.textContent = `?? ${unit}`
      }
    } else {
      this.replaySpeedDisplayTarget.textContent = `?? ${unit}`
    }
  }

  /**
   * Update day count display
   * @private
   */
  _updateReplayDayCount() {
    if (!this.hasReplayDayCountTarget || !this.replayManager) return

    const dayCount = this.replayManager.getDayCount()
    const currentIndex = this.replayManager.currentDayIndex + 1
    const pointCount = this.replayManager.getCurrentDayPointCount()

    this.replayDayCountTarget.textContent = `Day ${currentIndex} of ${dayCount} • ${pointCount.toLocaleString()} points`
  }

  /**
   * Render data density visualization on scrubber track
   * @private
   */
  _renderReplayDensity() {
    if (!this.hasReplayDensityContainerTarget || !this.replayManager) return

    // Use 48 segments (30-minute chunks)
    const segments = 48
    const density = this.replayManager.getDataDensity(segments)

    // Clear existing bars using DOM methods
    while (this.replayDensityContainerTarget.firstChild) {
      this.replayDensityContainerTarget.removeChild(
        this.replayDensityContainerTarget.firstChild,
      )
    }

    // Create density bars using DOM methods
    density.forEach((value) => {
      const bar = document.createElement("div")
      bar.className = "replay-density-bar"

      if (value > 0) {
        bar.classList.add("has-data")
        if (value > 0.5) {
          bar.classList.add("high-density")
        }
      }

      this.replayDensityContainerTarget.appendChild(bar)
    })
  }

  /**
   * Update cycle controls visibility and count
   * @private
   */
  _updateReplayCycleControls(minute) {
    if (!this.hasReplayCycleControlsTarget || !this.replayManager) return

    const count = this.replayManager.getPointCountAtMinute(minute)

    if (count > 1) {
      this.replayCycleControlsTarget.classList.remove("hidden")
      if (this.hasReplayPointCounterTarget) {
        const currentIndex = (this.replayManager.cycleIndex % count) + 1
        this.replayPointCounterTarget.textContent = `Point ${currentIndex} of ${count}`
      }
    } else {
      this.replayCycleControlsTarget.classList.add("hidden")
    }
  }

  /**
   * Hide cycle controls
   * @private
   */
  _hideReplayCycleControls() {
    if (this.hasReplayCycleControlsTarget) {
      this.replayCycleControlsTarget.classList.add("hidden")
    }
  }

  // ===== Replay Playback Methods =====

  /**
   * Toggle replay play/pause
   */
  replayTogglePlayback() {
    if (this.replayActive) {
      this._stopReplayPlayback()
    } else {
      this._startReplayPlayback()
    }
  }

  /**
   * Handle speed slider change
   */
  replaySpeedChange(event) {
    const speedIndex = parseInt(event.target.value, 10)
    const speeds = [1, 2, 5, 10]
    this.replaySpeed = speeds[speedIndex - 1] || 2

    if (this.hasReplaySpeedLabelTarget) {
      this.replaySpeedLabelTarget.textContent = `${this.replaySpeed}x`
    }
  }

  /**
   * Start replay animation
   * @private
   */
  _startReplayPlayback() {
    if (this.replayActive) return
    if (!this.replayManager || !this.hasReplayScrubberTarget) return

    // Get points for current day
    const currentDay = this.replayManager.getCurrentDay()
    if (!currentDay) return

    const dayPoints = this.replayManager.pointsByDay[currentDay]
    if (!dayPoints || dayPoints.length === 0) return

    this.replayActive = true
    this.replaySpeed = this.replaySpeed || 2
    this.replayPoints = dayPoints
    this.replayPointIndex = 0

    // Find starting index based on current scrubber position
    const currentMinute = parseInt(this.replayScrubberTarget.value, 10)
    for (let i = 0; i < dayPoints.length; i++) {
      const timestamp = this.replayManager._getTimestamp(dayPoints[i])
      const pointTime = this._parseReplayTimestamp(timestamp)
      if (pointTime) {
        const date = new Date(pointTime)
        const pointMinute = date.getHours() * 60 + date.getMinutes()
        if (pointMinute >= currentMinute) {
          this.replayPointIndex = i
          break
        }
      }
    }

    // Initialize interpolation coordinates
    const startPoint = dayPoints[this.replayPointIndex]
    const nextPoint = dayPoints[this.replayPointIndex + 1]
    this.replayCurrentCoords = startPoint
      ? this.replayManager.getCoordinates(startPoint)
      : null
    this.replayNextCoords = nextPoint
      ? this.replayManager.getCoordinates(nextPoint)
      : this.replayCurrentCoords

    // Show marker at starting point immediately
    if (startPoint) {
      this._showReplayMarker(startPoint)
      this._flyToReplayPoint(startPoint, true)
      this._highlightReplayRouteSegment(startPoint)
    }

    // Update UI
    if (this.hasReplayPlayButtonTarget) {
      this.replayPlayButtonTarget.classList.add("playing")
    }
    if (this.hasReplayPlayIconTarget) {
      this.replayPlayIconTarget.classList.add("hidden")
    }
    if (this.hasReplayPauseIconTarget) {
      this.replayPauseIconTarget.classList.remove("hidden")
    }

    this.replayLastTime = performance.now()

    // Start animation loop
    this._replayFrame()
  }

  /**
   * Stop replay animation
   * @private
   */
  _stopReplayPlayback() {
    // Guard against early calls before initialization
    if (this.replayActive === undefined) return

    this.replayActive = false

    // Cancel animation frame
    if (this.replayAnimationId) {
      cancelAnimationFrame(this.replayAnimationId)
      this.replayAnimationId = null
    }

    // Update UI
    if (this.hasReplayPlayButtonTarget) {
      this.replayPlayButtonTarget.classList.remove("playing")
    }
    if (this.hasReplayPlayIconTarget) {
      this.replayPlayIconTarget.classList.remove("hidden")
    }
    if (this.hasReplayPauseIconTarget) {
      this.replayPauseIconTarget.classList.add("hidden")
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
  _replayFrame() {
    if (!this.replayActive) return

    const now = performance.now()
    const elapsed = now - this.replayLastTime

    // Calculate interval between points based on speed
    // Speed 1x = 1 point per 500ms, Speed 10x = 1 point per 50ms
    const intervalMs = 500 / this.replaySpeed

    // Calculate interpolation progress (0 to 1) - use linear for smooth constant speed
    const progress = Math.min(elapsed / intervalMs, 1)

    // Interpolate marker position between current and next point
    let currentLon, currentLat
    if (this.replayCurrentCoords && this.replayNextCoords) {
      currentLon =
        this.replayCurrentCoords.lon +
        (this.replayNextCoords.lon - this.replayCurrentCoords.lon) * progress
      currentLat =
        this.replayCurrentCoords.lat +
        (this.replayNextCoords.lat - this.replayCurrentCoords.lat) * progress

      // Update marker position smoothly
      this._showReplayMarkerAt(currentLon, currentLat)

      // Smoothly pan map to keep marker visible (check every frame for smoothness)
      this._panMapToFollowMarker(currentLon, currentLat)
    }

    // When interval is complete, move to next point
    if (elapsed >= intervalMs) {
      this.replayLastTime = now

      // Move to next point
      this.replayPointIndex++

      // Check if we've reached the end of points for this day
      if (this.replayPointIndex >= this.replayPoints.length) {
        // Try to go to next day
        if (this.replayManager.canGoNext()) {
          this.replayManager.nextDay()
          this._updateReplayDayDisplay()
          this._updateReplayDayCount()
          this._updateReplayDayButtons()
          this._renderReplayDensity()

          // Get points for new day
          const newDay = this.replayManager.getCurrentDay()
          this.replayPoints = this.replayManager.pointsByDay[newDay] || []
          this.replayPointIndex = 0

          if (this.replayPoints.length === 0) {
            this._stopReplayPlayback()
            return
          }
        } else {
          // End of data, stop replay
          this._stopReplayPlayback()
          return
        }
      }

      // Get current and next points for interpolation
      const currentPoint = this.replayPoints[this.replayPointIndex]
      const nextPoint = this.replayPoints[this.replayPointIndex + 1]

      if (!currentPoint) {
        this._stopReplayPlayback()
        return
      }

      // Store coordinates for interpolation
      this.replayCurrentCoords = this.replayManager.getCoordinates(currentPoint)
      this.replayNextCoords = nextPoint
        ? this.replayManager.getCoordinates(nextPoint)
        : this.replayCurrentCoords

      // Update speed display for current point
      this._updateReplaySpeedDisplay(this._getPointVelocity(currentPoint))

      // Get minute for this point to update scrubber
      const timestamp = this.replayManager._getTimestamp(currentPoint)
      const pointTime = this._parseReplayTimestamp(timestamp)
      if (pointTime) {
        const date = new Date(pointTime)
        const minute = date.getHours() * 60 + date.getMinutes()

        // Update scrubber position
        this.replayScrubberTarget.value = minute

        // Update time display
        this._updateReplayTimeDisplay(minute, false)
      }

      // Highlight route segment (less frequently to reduce overhead)
      if (this.replayPointIndex % 5 === 0) {
        this._highlightReplayRouteSegment(currentPoint)
      }

      // Hide cycle controls during replay
      this._hideReplayCycleControls()
    }

    // Continue animation
    this.replayAnimationId = requestAnimationFrame(() => this._replayFrame())
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
   * Show replay marker at specific coordinates (for interpolation)
   * @private
   */
  _showReplayMarkerAt(lon, lat) {
    if (lon === undefined || lat === undefined) return

    const replayMarkerLayer = this.layerManager?.getLayer("replayMarker")
    if (replayMarkerLayer) {
      replayMarkerLayer.showMarker(lon, lat)
    }
  }

  /**
   * Initialize replay state
   * @private
   */
  _initializeReplayState() {
    this.replayActive = false
    this.replaySpeed = 2
    this.replayPoints = []
    this.replayPointIndex = 0
    this.replayLastTime = 0
    this.replayAnimationId = null
    this.replayCurrentCoords = null
    this.replayNextCoords = null
    // Set initial speed label
    if (this.hasReplaySpeedLabelTarget) {
      this.replaySpeedLabelTarget.textContent = "2x"
    }
    if (this.hasReplaySpeedSliderTarget) {
      this.replaySpeedSliderTarget.value = 2
    }
  }

  /**
   * Show replay marker at point location
   * @private
   */
  _showReplayMarker(point) {
    const coords = this.replayManager?.getCoordinates(point)
    if (!coords) return

    const replayMarkerLayer = this.layerManager?.getLayer("replayMarker")
    if (replayMarkerLayer) {
      replayMarkerLayer.showMarker(coords.lon, coords.lat, {
        timestamp: this.replayManager._getTimestamp(point),
      })
    }
  }

  /**
   * Clear replay marker
   * @private
   */
  _clearReplayMarker() {
    const replayMarkerLayer = this.layerManager?.getLayer("replayMarker")
    if (replayMarkerLayer) {
      replayMarkerLayer.clear()
    }
  }

  /**
   * Fly map to replay point
   * @private
   * @param {Object} point - Point object
   * @param {boolean} fast - Use faster animation (for replay)
   */
  _flyToReplayPoint(point, fast = false) {
    const coords = this.replayManager?.getCoordinates(point)
    if (!coords || !this.map) return

    this.map.flyTo({
      center: [coords.lon, coords.lat],
      zoom: Math.max(this.map.getZoom(), 14),
      duration: fast ? 100 : 500,
    })
  }

  /**
   * Highlight route segment containing the replay point
   * @private
   */
  _highlightReplayRouteSegment(point) {
    const routesLayer = this.layerManager?.getLayer("routes")
    if (!routesLayer) return

    const coords = this.replayManager?.getCoordinates(point)
    if (!coords) return

    // Query the routes source to find feature containing this point
    const routesSource = this.map?.getSource("routes-source")
    if (!routesSource?._data?.features) {
      routesLayer.setHoverRoute(null)
      return
    }

    const timestamp = this.replayManager._getTimestamp(point)
    if (!timestamp) {
      routesLayer.setHoverRoute(null)
      return
    }

    // Parse timestamp consistently (handle both Unix seconds and milliseconds)
    const pointTime = this._parseReplayTimestamp(timestamp)

    // Find the route segment containing this timestamp
    const matchingFeature = routesSource._data.features.find((feature) => {
      const startTime = feature.properties?.startTime
      const endTime = feature.properties?.endTime

      if (startTime && endTime) {
        const start = this._parseReplayTimestamp(startTime)
        const end = this._parseReplayTimestamp(endTime)
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
  _parseReplayTimestamp(timestamp) {
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
   * Clear replay route highlight
   * @private
   */
  _clearReplayRouteHighlight() {
    const routesLayer = this.layerManager?.getLayer("routes")
    if (routesLayer) {
      routesLayer.setHoverRoute(null)
    }
  }
}
