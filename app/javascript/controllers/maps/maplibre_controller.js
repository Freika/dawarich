import { Controller } from "@hotwired/stimulus"
import { Toast } from "maps_maplibre/components/toast"
import { ReplayPanel } from "maps_maplibre/managers/replay_panel"
import { ApiClient } from "maps_maplibre/services/api_client"
import { CleanupHelper } from "maps_maplibre/utils/cleanup_helper"
import { featureToPhoto } from "maps_maplibre/utils/feature_to_photo"
import { cancelAllPreviews } from "maps_maplibre/utils/layer_gate"
import { loadLastView, saveView } from "maps_maplibre/utils/map_view_store"
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
    userPlan: { type: String, default: "pro" },
    upgradeUrl: { type: String, default: "" },
    importId: { type: String, default: "" },
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
    "stayMaxGapMinutesValue",
    "gpsAccuracyThresholdValue",
    "gpsFilteringToggle",
    // Search
    "searchInput",
    "searchResults",
    // Layer toggles
    "pointsToggle",
    "routesToggle",
    "heatmapToggle",
    "hexagonsToggle",
    "visitsToggle",
    "photosToggle",
    "areasToggle",
    "placesToggle",
    "fogToggle",
    "scratchToggle",
    "anomaliesToggle",
    "familyToggle",
    "flightsToggle",
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
    "deletePointsButton",
    "deleteButtonText",
    "deleteAnomaliesButton",
    "deleteAnomaliesButtonText",
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
    // Transportation enabled modes allowlist
    "enabledModeCheckbox",
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
    // Timeline feed
    "timelineFeedContainer",
    // Replay playback
    "replayPlayButton",
    "replayFollowButton",
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
    // Reset in case this controller instance is reconnected after a prior
    // disconnect (so the mid-init teardown guard doesn't fire on a fresh map).
    this._disconnected = false

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

    // When the page loads with the Timeline panel open (deep link or
    // SPA-style nav from elsewhere), the visits layer is always relevant —
    // it's the on-map counterpart of the rail. Force it on for this session
    // even if the user's saved layer toggle is off, without persisting back
    // to the server.
    const urlParams = new URLSearchParams(window.location.search)
    if (urlParams.get("panel") === "timeline") {
      this.settings.visitsEnabled = true
      this.settingsController.settings.visitsEnabled = true
    }

    // Sync toggle states with loaded settings
    this.settingsController.syncToggleStates()

    await this.initializeMap()
    // initializeMap bails without setting this.map if the controller
    // disconnected mid-init (fast Turbo nav); don't build managers on a
    // dead controller with an undefined map.
    if (this._disconnected) return

    this.initializeAPI()

    // Initialize managers
    this.layerManager = new LayerManager(
      this.map,
      this.settings,
      this.api,
      this,
    )
    this.dataLoader = new DataLoader(this.api, this.apiKeyValue, this.settings)
    this.eventHandlers = new EventHandlers(this.map, this)
    this.filterManager = new FilterManager(this.dataLoader)
    this.mapDataManager = new MapDataManager(this)

    // Initialize feature managers
    this.areaSelectionManager = new AreaSelectionManager(this)
    this.visitsManager = new VisitsManager(this)
    // The moveend viewport-refetch normally attaches when the user flips the
    // Visits toggle on. When the layer starts enabled (saved setting or the
    // panel=timeline force-enable above), attach it here so panning keeps
    // the dots in sync with the viewport.
    if (this.settings.visitsEnabled) {
      this.visitsManager.attachViewportRefetch()
    }
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

    // SPA date-range change from the Timeline calendar — refetch all enabled
    // layers for the new start/end without tearing down the map instance.
    this.boundHandleDateNavigated = this.handleTimelineDateNavigated.bind(this)
    this.cleanup.addEventListener(
      document,
      "timeline-feed:date-navigated",
      this.boundHandleDateNavigated,
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

    // Re-use the same refresh path for area edits — both create and update
    // need the areas layer rebuilt from the API.
    this.cleanup.addEventListener(
      document,
      "area:updated",
      this.boundHandleAreaCreated,
    )

    // Format initial dates
    this.startDateValue = DateManager.formatDateForAPI(
      new Date(this.startDateValue),
    )
    this.endDateValue = DateManager.formatDateForAPI(
      new Date(this.endDateValue),
    )

    if (this.settings.placesEnabled) {
      await this.placesManager.initializePlaceTagFilters({
        reloadPlaces: false,
      })
    }

    this.loadMapData().then(() => {
      if (this.settings?.familyEnabled) {
        this.loadFamilyMembers()
      }
      if (this.settings?.anomaliesEnabled) {
        this.routesManager.refreshAnomalies({ enabled: true })
      }
    })

    // Show family members list immediately (doesn't depend on layer)
    if (this.settings?.familyEnabled && this.hasFamilyMembersListTarget) {
      this.familyMembersListTarget.style.display = "block"
    }
  }

  disconnect() {
    this._disconnected = true
    if (this._familyHistoryTimer) clearTimeout(this._familyHistoryTimer)
    this.replayPanel?.destroy()
    this.settingsController?.stopRecalculationPolling()
    this.searchManager?.destroy()
    this.visitsManager?.destroy()
    this.eventHandlers?.destroy()
    cancelAllPreviews()
    if (this._persistView) this.map?.off("moveend", this._persistView)
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
    // Reopen at the user's last viewport instead of the zoomed-out globe.
    // When the date range has data, fitBounds overrides this; when it has
    // none, the map stays on the last-known view rather than the world.
    const lastView = loadLastView(this.apiKeyValue)

    const map = await MapInitializer.initialize(this.containerTarget, {
      mapStyle: this.settings.mapStyle,
      globeProjection: this.settings.globeProjection,
      hiddenTileCategories: this.settings.hiddenTileCategories || [],
      disabledPoiGroups: this.settings.disabledPoiGroups || [],
      customTheme: this.settings.customTheme,
      vectorTilesUrl: this.settings.vectorTilesUrl,
      ...(lastView ? { center: lastView.center, zoom: lastView.zoom } : {}),
    })

    // The controller may have disconnected while the style was loading (e.g.
    // fast Turbo navigation). Tear the map down instead of attaching a listener
    // to an orphaned instance that disconnect() can no longer reach.
    if (this._disconnected) {
      map.remove()
      return
    }

    this.map = map
    this._persistView = () => saveView(this.map, this.apiKeyValue)
    this.map.on("moveend", this._persistView)
  }

  /**
   * Initialize API client
   */
  initializeAPI() {
    this.api = new ApiClient(this.apiKeyValue, this.importIdValue || null)
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
    this.debouncedLoadFamilyHistory()
  }

  /**
   * Timeline panel requested a new day (SPA navigation — no page reload).
   * Mirrors `monthChanged` exactly, including the date format: the Points/Tracks
   * API expects `DateManager.formatDateForAPI`'s local `YYYY-MM-DDTHH:MM+OFFSET`
   * shape. Using `Date#toISOString()` (UTC `Z` suffix) here was causing Tracks
   * to come back empty because the server parsed the dates differently.
   */
  handleTimelineDateNavigated(event) {
    const { startAt, endAt } = event.detail || {}
    if (!startAt || !endAt) return

    const toApiDate = (local) => {
      const d = new Date(local)
      if (Number.isNaN(d.getTime())) return null
      return DateManager.formatDateForAPI(d)
    }
    const start = toApiDate(startAt)
    const end = toApiDate(endAt)
    if (!start || !end) return

    this.startDateValue = start
    this.endDateValue = end

    this._clearDayHighlight?.()
    this.loadMapData().then(() => {
      if (this.settings?.anomaliesEnabled) {
        this.routesManager.refreshAnomalies({ enabled: true })
      }
    })
    this.refreshTimelineFeedIfActive?.()
    this.debouncedLoadFamilyHistory?.()
  }

  debouncedLoadFamilyHistory() {
    if (this._familyHistoryTimer) clearTimeout(this._familyHistoryTimer)
    this._familyHistoryTimer = setTimeout(() => this.loadFamilyHistory(), 300)
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
      const isOpening = !this.settingsPanelTarget.classList.contains("open")
      this.settingsPanelTarget.classList.toggle("open")

      // Shrink/expand map container
      if (this.hasContainerTarget) {
        this.containerTarget.classList.toggle("panel-open", isOpening)
        // The Timeline tab puts the map container in `panel-timeline-expanded`
        // (720px-wide panel + matching margin-left). When the user closes the
        // panel we have to clear that too — otherwise the panel slides
        // off-screen but the map keeps its 720px left margin and the user
        // sees an empty dark column where the panel used to be.
        if (!isOpening) {
          this.containerTarget.classList.remove("panel-timeline-expanded")
          this.settingsPanelTarget.classList.remove("timeline-expanded")
          // Cluster doubles as the panel's tab strip — clear its active
          // state when the panel is dismissed (e.g. via the header X) so
          // users don't see a button still highlighted with no panel open.
          document.dispatchEvent(new CustomEvent("map-panel:closed"))
        }
        // Tell MapLibre to recalculate after the CSS transition
        setTimeout(() => this.map?.resize(), 350)
      }
    }
  }

  /**
   * Handle tab change events from the map panel controller
   */
  handleTabChanged(event) {
    const { tab } = event.detail
    if (tab === "timeline-feed") {
      this.loadTimelineFeed()
      // The timeline rail is the on-panel counterpart of the visits map
      // layer — keep them in sync. If the visits layer is currently off,
      // turn it on (session-only, no persistence) so the dots appear next
      // to the day's entries.
      this._ensureVisitsLayerEnabled()
    } else if (this._highlightedDay) {
      // Leaving timeline-feed tab — restore full opacity
      this._clearDayHighlight()
    }
  }

  // Force-enables the visits layer for this session without persisting the
  // change to the server — the user's saved Layers preference shouldn't be
  // flipped just because they opened Timeline once.
  //
  // We DO update the in-memory `settings.visitsEnabled` so subsequent
  // `loadMapData()` calls (e.g. when the user navigates to a different
  // day) include visits in the fetch + the loading-counter expectations.
  // Otherwise the loader badge reads "N tracks" only and the map ends
  // up with stale visits when a new day is selected.
  async _ensureVisitsLayerEnabled() {
    if (!this.hasVisitsToggleTarget) return

    // In-memory only — don't go through SettingsManager.updateSetting,
    // which would persist back to the server.
    if (this.settings) this.settings.visitsEnabled = true
    if (this.dataLoader?.settings) this.dataLoader.settings.visitsEnabled = true
    if (this.settingsController?.settings) {
      this.settingsController.settings.visitsEnabled = true
    }

    if (this.visitsToggleTarget.checked) return
    this.visitsToggleTarget.checked = true
    if (this.hasVisitsSearchTarget) {
      this.visitsSearchTarget.style.display = "block"
    }

    const visitsLayer = this.layerManager?.getLayer("visits")
    if (!visitsLayer) return

    try {
      if (!visitsLayer.data?.features?.length) {
        const visits = await this.api.fetchVisits({
          start_at: this.startDateValue,
          end_at: this.endDateValue,
        })
        this.filterManager?.setAllVisits(visits)
        visitsLayer.update(this.dataLoader.visitsToGeoJSON(visits))
      }
      visitsLayer.show()
    } catch (err) {
      console.error("Failed to auto-enable visits layer for timeline:", err)
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
    this._safeSetLayout("visits-labels", "symbol-sort-key", undefined)

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
    this._safeSetLayout("visits-labels", "symbol-sort-key", undefined)
    this._safeSetPaint("tracks", "line-opacity", 0.7)
  }

  /**
   * Handle entry-hover events from the timeline feed.
   * Highlights the matching route/visit on the map by dimming everything else.
   */
  handleEntryHover(event) {
    const { entryType, startedAt, endedAt, trackId, visitId } = event.detail
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

    // Visits:
    //   - Visit hover  → only the hovered visit stays full opacity; others are
    //     dimmed so the on-map dot the rail row points to is unambiguous.
    //   - Journey hover → no visit is the focus, so all visits fade nearly out;
    //     the eye lands on the highlighted track instead.
    if (entryType === "visit") {
      // Match by visit id rather than by ISO `started_at` range — the
      // API returns timestamps with milliseconds (`...:00.000Z`) while
      // DayAssembler renders the row attribute with second precision
      // (`...:00Z`). Lexicographic comparison fails the equality check
      // and dims the hovered visit along with the others.
      const visitExpr = [
        "case",
        ["==", ["get", "id"], Number(visitId)],
        1,
        0.15,
      ]
      this._safeSetPaint("visits", "circle-opacity", visitExpr)
      this._safeSetPaint("visits", "circle-stroke-opacity", visitExpr)
      this._safeSetPaint("visits-labels", "text-opacity", visitExpr)

      // Labels collide-hide by default, so a neighbouring (dimmed) visit's
      // label can win placement over the hovered one and the text under the
      // bright dot fades out. Give the hovered visit the lowest sort key so
      // its label is placed first and always survives collision.
      this._safeSetLayout("visits-labels", "symbol-sort-key", [
        "case",
        ["==", ["get", "id"], Number(visitId)],
        0,
        1,
      ])
    } else {
      const VISITS_NEARLY_INVISIBLE = 0.05
      this._safeSetPaint("visits", "circle-opacity", VISITS_NEARLY_INVISIBLE)
      this._safeSetPaint(
        "visits",
        "circle-stroke-opacity",
        VISITS_NEARLY_INVISIBLE,
      )
      this._safeSetPaint(
        "visits-labels",
        "text-opacity",
        VISITS_NEARLY_INVISIBLE,
      )
      this._safeSetLayout("visits-labels", "symbol-sort-key", undefined)
    }

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

    this._removeHoverPopup()

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

  _safeSetLayout(layerId, property, value) {
    if (this.map.getLayer(layerId)) {
      this.map.setLayoutProperty(layerId, property, value)
    }
  }

  _removeHoverPopup() {
    if (this._hoverPopup) {
      this._hoverPopup.remove()
      this._hoverPopup = null
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

    // Clear any hover popup from previous day
    this._removeHoverPopup()

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

    // Store override state for restoration (only on first override)
    if (!this._visitsOverride) {
      const source = this.map.getSource(visitsLayer.sourceId)
      this._visitsOverride = {
        wasHidden,
        previousData: source?._data || {
          type: "FeatureCollection",
          features: [],
        },
      }
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
  applyMapStyle(styleName) {
    return this.settingsController.applyMapStyle(styleName)
  }
  resetSettings() {
    return this.settingsController.resetSettings()
  }
  toggleTileCategory(event) {
    return this.settingsController.toggleTileCategory(event)
  }
  togglePoiGroup(event) {
    return this.settingsController.togglePoiGroup(event)
  }
  updateDistanceUnit(event) {
    return this.settingsController.updateDistanceUnit(event)
  }
  updateVectorTilesUrl(event) {
    return this.settingsController.updateVectorTilesUrl(event)
  }
  updateRouteColor(event) {
    return this.settingsController.updateRouteColor(event)
  }
  updateTrackColor(event) {
    return this.settingsController.updateTrackColor(event)
  }
  resetLayerColors() {
    return this.settingsController.resetLayerColors()
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
  updateStayMaxGapMinutesDisplay(event) {
    return this.settingsController.updateStayMaxGapMinutesDisplay(event)
  }
  updateGpsAccuracyThresholdDisplay(event) {
    return this.settingsController.updateGpsAccuracyThresholdDisplay(event)
  }
  reapplyAnomalyFilter() {
    return this.settingsController.reapplyAnomalyFilter()
  }
  recalculateUserData() {
    return this.settingsController.recalculateUserData()
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
  deleteSelectedAnomalies() {
    return this.areaSelectionManager.deleteSelectedAnomalies()
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

      // If the area info card is open for an edited area, refresh its name
      // in place so the side panel matches the map.
      this.eventHandlers?.refreshActiveAreaInfo(areas)

      Toast.success("Area created successfully!")
    } catch (_error) {
      Toast.error("Failed to reload areas")
    }
  }

  // Routes Manager methods
  togglePoints(event) {
    return this.routesManager.togglePoints(event)
  }

  togglePointsEditing(event) {
    const pointsLayer = this.layerManager.getLayer("points")
    pointsLayer?.setEditMode(event.currentTarget.checked)
  }
  toggleRoutes(event) {
    return this.routesManager.toggleRoutes(event)
  }
  toggleHeatmap(event) {
    return this.routesManager.toggleHeatmap(event)
  }
  toggleHexagons(event) {
    return this.routesManager.toggleHexagons(event)
  }
  updateFogMode(event) {
    return this.settingsController.updateFogMode(event)
  }

  toggleFog(event) {
    return this.routesManager.toggleFog(event)
  }
  toggleScratch(event) {
    return this.routesManager.toggleScratch(event)
  }
  async togglePhotos(event) {
    await this.routesManager.togglePhotos(event)
    if (!this.replayPanel?.isOpen) return
    if (!event.target.checked) this._photosWasVisible = false
    this.replayPanel.refreshReplayPhotos()
  }
  toggleAreas(event) {
    return this.routesManager.toggleAreas(event)
  }
  toggleTracks(event) {
    return this.routesManager.toggleTracks(event)
  }
  toggleFlights(event) {
    return this.routesManager.toggleFlights(event)
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
  toggleAnomalies(event) {
    return this.routesManager.toggleAnomalies(event)
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

      // Load history polylines
      this.loadFamilyHistory()
    } catch (error) {
      console.error("[Maps V2] Failed to load family members:", error)
      Toast.error("Failed to load family members")
    }
  }

  async loadFamilyHistory() {
    try {
      const startAt = this.startDateValue
      const endAt = this.endDateValue
      if (!startAt || !endAt) return

      const params = new URLSearchParams({ start_at: startAt, end_at: endAt })
      const response = await fetch(
        `/api/v1/families/locations/history?${params}`,
        {
          headers: {
            Accept: "application/json",
            "Content-Type": "application/json",
            Authorization: `Bearer ${this.apiKeyValue}`,
          },
        },
      )

      if (!response.ok) return

      const data = await response.json()
      const members = data.members || []

      const familyLayer = this.layerManager.getLayer("family")
      if (familyLayer) {
        if (members.length > 0) {
          // Assign colors consistent with member markers
          for (const member of members) {
            member.color = this.getFamilyMemberColor(member.user_id)
          }
          familyLayer.loadMemberHistory(members)
        } else {
          familyLayer.clearHistory()
        }
      }

      // Update member info lines with sharing_since data
      this._familyHistoryData = members
      this.updateFamilyInfoLines(members)
    } catch (error) {
      console.error("[Maps V2] Failed to load family history:", error)
    }
  }

  updateFamilyInfoLines(historyMembers) {
    if (!this.hasFamilyMembersContainerTarget) return

    for (const member of historyMembers) {
      const infoEl = this.familyMembersContainerTarget.querySelector(
        `[data-member-info="${member.user_id}"]`,
      )
      if (!infoEl || !member.sharing_since) continue

      const sharingDate = new Date(member.sharing_since)
      const daysSharing = Math.min(
        365,
        Math.floor(
          (Date.now() - sharingDate.getTime()) / (1000 * 60 * 60 * 24),
        ),
      )
      const formattedDate = sharingDate.toLocaleDateString("en-US", {
        month: "short",
        day: "numeric",
      })

      infoEl.textContent = `Sharing since ${formattedDate} (${daysSharing} day${daysSharing !== 1 ? "s" : ""} of history)`
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

    container.replaceChildren(
      ...locations.map((location) => {
        const emailInitial = location.email?.charAt(0)?.toUpperCase() || "?"
        const color = this.getFamilyMemberColor(location.user_id)
        const lastSeen = new Date(location.updated_at).toLocaleString("en-US", {
          timeZone: this.timezoneValue || "UTC",
          month: "short",
          day: "numeric",
          hour: "numeric",
          minute: "2-digit",
        })

        const row = document.createElement("div")
        row.className =
          "flex items-center gap-2 p-2 hover:bg-base-200 rounded-lg cursor-pointer transition-colors"
        row.dataset.action = "click->maps--maplibre#centerOnFamilyMember"
        row.dataset.memberId = location.user_id

        const avatar = document.createElement("div")
        Object.assign(avatar.style, {
          backgroundColor: color,
          color: "white",
          borderRadius: "50%",
          width: "24px",
          height: "24px",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          fontSize: "12px",
          fontWeight: "bold",
          flexShrink: "0",
        })
        avatar.textContent = emailInitial

        const info = document.createElement("div")
        info.className = "flex-1 min-w-0"

        const emailDiv = document.createElement("div")
        emailDiv.className = "text-sm font-medium truncate"
        emailDiv.textContent = location.email || "Unknown"

        const timeDiv = document.createElement("div")
        timeDiv.className = "text-xs text-base-content/60"
        timeDiv.textContent = lastSeen

        const statusDiv = document.createElement("div")
        statusDiv.className = "text-xs text-info/70"
        statusDiv.dataset.memberInfo = location.user_id

        info.append(emailDiv, timeDiv, statusDiv)
        row.append(avatar, info)
        return row
      }),
    )
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

    // Reset the tracked entity; area clicks re-tag this after calling showInfo.
    this._infoEntity = null

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
      case "point":
        this.deletePoint(id)
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
   * Fetch an area and dispatch `area:edit` so the area_creation_v2
   * controller opens its modal in edit mode. Triggered from the area
   * info card's Edit button.
   */
  async openAreaEditModal(event) {
    const areaId = event.currentTarget?.dataset?.id
    if (!areaId) return

    try {
      const response = await fetch(`/api/v1/areas/${areaId}`, {
        headers: {
          Authorization: `Bearer ${this.apiKeyValue}`,
          "Content-Type": "application/json",
        },
      })
      if (!response.ok) {
        throw new Error(`Failed to fetch area: ${response.status}`)
      }
      const area = await response.json()
      document.dispatchEvent(
        new CustomEvent("area:edit", { detail: { area }, bubbles: true }),
      )
    } catch (_error) {
      Toast.error("Failed to load area details")
    }
  }

  /**
   * Delete a single point with confirmation, then remove it from the points
   * source and rebuild the connecting routes so the map updates without a
   * full reload.
   */
  async deletePoint(pointId) {
    const confirmed = confirm(
      "Delete this point?\n\nThis action cannot be undone.",
    )
    if (!confirmed) return

    const numericId = Number(pointId)
    const pointsLayer = this.layerManager.getLayer("points")
    const source = pointsLayer && this.map.getSource(pointsLayer.sourceId)
    const data = source?._data
    const removedIndex =
      data?.features?.findIndex(
        (f) => Number(f.properties?.id) === numericId,
      ) ?? -1
    const removedFeature =
      removedIndex >= 0 ? data.features[removedIndex] : undefined
    const canReconcile = Boolean(data?.features && removedFeature)

    // The cached full point set feeds route rebuilds and the scratch layer
    // in simplified rendering mode — keep it in sync with the layer data.
    const cachedPoints = this.mapDataManager?.lastLoadedData?.points
    const removedCacheIndex =
      cachedPoints?.findIndex((p) => Number(p.id) === numericId) ?? -1
    const removedCachePoint =
      removedCacheIndex >= 0 ? cachedPoints[removedCacheIndex] : undefined

    // The API delete fires regardless of layer reconciliation, so the cache
    // must always drop the point too.
    if (removedCachePoint) cachedPoints.splice(removedCacheIndex, 1)

    // Optimistically remove the point so the map updates instantly; the API
    // call and route rebuild run in the background and are reverted on error.
    if (canReconcile) {
      data.features = data.features.filter(
        (f) => Number(f.properties?.id) !== numericId,
      )
      source.setData(data)
      pointsLayer.data = data
      this.routesManager.reloadRoutes().catch((error) => console.error(error))
    }

    try {
      await this.api.deletePoint(pointId)
      this.closeInfo()
      Toast.success("Point deleted successfully")
    } catch (_error) {
      // The point still exists server-side, so restore it in the cache even
      // when the layer reconcile below is skipped.
      if (removedCachePoint && !cachedPoints.includes(removedCachePoint)) {
        cachedPoints.splice(
          Math.min(removedCacheIndex, cachedPoints.length),
          0,
          removedCachePoint,
        )
      }

      // Reconcile against the source's CURRENT data, re-read fresh: a realtime
      // broadcast may have replaced it while the request was in flight, so the
      // snapshot captured above could be stale and would clobber that update.
      const currentSource =
        pointsLayer && this.map?.getSource(pointsLayer.sourceId)
      const currentData = currentSource?._data
      if (currentData?.features && removedFeature) {
        // Splice back at the original index so the restored point keeps its
        // render order instead of jumping on top of every other point.
        const features = [...currentData.features]
        features.splice(
          Math.min(removedIndex, features.length),
          0,
          removedFeature,
        )
        currentData.features = features
        currentSource.setData(currentData)
        pointsLayer.data = currentData
        this.routesManager.reloadRoutes().catch((error) => console.error(error))
      }
      Toast.error("Failed to delete point")
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

  // ===== Replay (delegates to the reusable ReplayPanel) =====

  _ensureReplayPanel() {
    if (this.replayPanel) return
    this.replayPanel = new ReplayPanel({
      controller: this,
      map: this.map,
      timezone: this.timezoneValue,
      markerLayer: () => this.layerManager?.getLayer("replayMarker"),
      loadPoints: async () => {
        await this.mapDataManager.ensurePointsLoaded()
        return this._getLoadedPoints()
      },
      highlightPoint: (point) => this._highlightReplayRouteSegment(point),
      clearHighlight: () => this._clearReplayRouteHighlight(),
      onPlayStateChange: (playing) => this._updateTrackReplayButton(playing),
      getPhotos: () => {
        const layer = this.layerManager?.getLayer("photos")
        const features = layer?.visible ? layer.data?.features : null
        return features?.length ? features.map(featureToPhoto) : []
      },
      onReplayPhotosActive: (active) => {
        const layer = this.layerManager?.getLayer("photos")
        if (!layer) return
        if (active) {
          this._photosWasVisible = layer.visible
          layer.hide()
        } else if (this._photosWasVisible) {
          layer.show()
        }
      },
    })
  }

  async toggleReplay() {
    if (!this.hasReplayPanelTarget) return
    this._ensureReplayPanel()
    await this.replayPanel.toggle()
  }

  replayScrubberHover(event) {
    this.replayPanel?.scrubberHover(event)
  }

  replayCyclePrev() {
    this.replayPanel?.cyclePrev()
  }

  replayCycleNext() {
    this.replayPanel?.cycleNext()
  }

  replayTogglePlayback() {
    this.replayPanel?.togglePlayback()
  }

  replayRecenterFollow() {
    this.replayPanel?.recenterFollow()
  }

  replaySpeedChange(event) {
    this.replayPanel?.speedChange(event)
  }

  async replayTrack(event) {
    if (!this.hasReplayPanelTarget) return
    this._ensureReplayPanel()

    if (this.replayPanel.isPlaying) {
      this.replayPanel.stopPlayback()
      return
    }

    const isVisible = !this.replayPanelTarget.classList.contains("hidden")
    if (isVisible && this.replayPanel.manager?.hasData()) {
      this.replayPanel.startPlayback()
      return
    }

    const trackStart = event.currentTarget.dataset.trackStart
    if (!trackStart) return
    const trackDate = new Date(trackStart)
    if (Number.isNaN(trackDate.getTime())) return

    await this.replayPanel.ensureOpen()
    if (!this.replayPanel.manager?.hasData()) return

    const targetDay = `${trackDate.getFullYear()}-${String(trackDate.getMonth() + 1).padStart(2, "0")}-${String(trackDate.getDate()).padStart(2, "0")}`
    this.replayPanel.goToDay(targetDay)

    const startMinute = trackDate.getHours() * 60 + trackDate.getMinutes()
    this.replayPanel.setMinute(startMinute)
    this.replayPanel.startPlayback()
  }

  async toggleTrackPoints(event) {
    const target = event?.currentTarget
    if (!target) return
    const trackId = target.dataset.trackId
    if (!trackId) return
    const enabled = !!target.checked
    if (this.eventHandlers?._toggleTrackPoints) {
      await this.eventHandlers._toggleTrackPoints(trackId, enabled)
    }
  }

  _getLoadedPoints() {
    if (this.mapDataManager?.lastLoadedData?.points) {
      return this.mapDataManager.lastLoadedData.points
    }

    const pointsSource = this.map?.getSource("points-source")
    if (pointsSource?._data?.features) {
      return pointsSource._data.features
    }

    return []
  }

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

  _highlightReplayRouteSegment(point) {
    const routesLayer = this.layerManager?.getLayer("routes")
    if (!routesLayer) return

    const manager = this.replayPanel?.manager
    const coords = manager?.getCoordinates(point)
    if (!coords) return

    const routesSource = this.map?.getSource("routes-source")
    if (!routesSource?._data?.features) {
      routesLayer.setHoverRoute(null)
      return
    }

    const timestamp = manager?.getTimestamp(point)
    if (!timestamp) {
      routesLayer.setHoverRoute(null)
      return
    }

    const pointTime = this._parseReplayTimestamp(timestamp)

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

  _parseReplayTimestamp(timestamp) {
    if (!timestamp) return 0

    if (typeof timestamp === "string") {
      return new Date(timestamp).getTime()
    }

    if (typeof timestamp === "number") {
      if (timestamp < 10000000000) {
        return timestamp * 1000
      }
      return timestamp
    }

    return 0
  }

  _clearReplayRouteHighlight() {
    const routesLayer = this.layerManager?.getLayer("routes")
    if (routesLayer) {
      routesLayer.setHoverRoute(null)
    }
  }
}
