import { Controller } from "@hotwired/stimulus"
import { formatNumber, translate } from "i18n"
import { deletePlace } from "maps_maplibre/components/place_actions"
import { RangeStatistics } from "maps_maplibre/components/range_statistics"
import { Toast } from "maps_maplibre/components/toast"
import { PlacePanelBridge } from "maps_maplibre/editing/place_panel_bridge"
import { ReplayPanel } from "maps_maplibre/managers/replay_panel"
import { TimelineSegmentHover } from "maps_maplibre/managers/timeline_segment_hover"
import { ApiClient } from "maps_maplibre/services/api_client"
import { CleanupHelper } from "maps_maplibre/utils/cleanup_helper"
import { featureToPhoto } from "maps_maplibre/utils/feature_to_photo"
import { anomaliesVisible } from "maps_maplibre/utils/layer_dependencies"
import { cancelAllPreviews } from "maps_maplibre/utils/layer_gate"
import { loadLastView, saveView } from "maps_maplibre/utils/map_view_store"
import { performanceMonitor } from "maps_maplibre/utils/performance_monitor"
import { parseTimestamp } from "maps_maplibre/utils/realtime_date_filter"
import { SearchManager } from "maps_maplibre/utils/search_manager"
import { SettingsManager } from "maps_maplibre/utils/settings_manager"
import { syncSidebarLayout } from "maps_maplibre/utils/sidebar_layout"
import { setPrivacyZonesFingerprint } from "maps_maplibre/utils/tile_freshness"
import { AreaSelectionManager } from "./maplibre/area_selection_manager"
import { consumeCreatePlaceLink } from "./maplibre/create_place_link"
import { DataLoader } from "./maplibre/data_loader"
import { DateManager } from "./maplibre/date_manager"
import { EventHandlers } from "./maplibre/event_handlers"
import { FamilyManager } from "./maplibre/family_manager"
import { FilterManager } from "./maplibre/filter_manager"
import { LayerManager } from "./maplibre/layer_manager"
import { LayerVisibilityManager } from "./maplibre/layer_visibility_manager"
import { MapDataManager } from "./maplibre/map_data_manager"
import { MapInitializer } from "./maplibre/map_initializer"
import { PlacesManager } from "./maplibre/places_manager"
import { SettingsController } from "./maplibre/settings_manager"
import { TimelineMapBridge } from "./maplibre/timeline_map_bridge"
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
    gatedLayers: { type: Array, default: [] },
    dataWindowStart: { type: String, default: "" },
    upgradeUrl: { type: String, default: "" },
    importId: { type: String, default: "" },
    privacyZonesFingerprint: { type: String, default: "" },
    currentPosition: Object,
    explorationBounds: Array,
    explorationSnapshot: String,
    explorationMessages: Object,
  }

  static targets = [
    "container",
    "progressBadge",
    "progressBadgeText",
    "monthSelect",
    "clusterToggle",
    "settingsPanel",
    "visitsSearch",
    "placesFilters",
    "enableAllPlaceTagsToggle",
    "minMinutesInCityValue",
    "gpsFilteringToggle",
    "gpsAccuracyThresholdValue",
    // Search
    "searchInput",
    "searchResults",
    // Layer toggles
    "pointsToggle",
    "pointsEditToggle",
    "pointsEditUnavailableNote",
    "heatmapToggle",
    "hexagonsToggle",
    "visitsToggle",
    "photosToggle",
    "placesToggle",
    "placeBoundariesToggle",
    "fogToggle",
    "scratchToggle",
    "anomaliesToggle",
    "familyToggle",
    "flightsToggle",
    "tracksToggle",
    // Globe projection
    "globeToggle",
    // Family members
    "familyMembersList",
    "familyMembersContainer",
    // Area selection
    "selectAreaButton",
    "selectAllTimeCheckbox",
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
    // Transportation mode detection
    "transportationCollapseToggle",
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

    // A Turbo snapshot taken while the WebGL error was showing comes back
    // with it; start from the map view and let the checks below decide.
    this.containerTarget.classList.remove("hidden")
    this.webglErrorTarget.classList.add("hidden")

    if (!this.isWebGLSupported()) {
      this.showWebGLError()
      return
    }

    this.cleanup = new CleanupHelper()
    setPrivacyZonesFingerprint(this.privacyZonesFingerprintValue)

    // Initialize API and settings
    SettingsManager.initialize(this.apiKeyValue)
    this.familyManager = new FamilyManager(this)
    this.timelineBridge = new TimelineMapBridge(this)
    this.settingsController = new SettingsController(this)
    await this.loadViewSettings()

    // Sync toggle states with loaded settings
    this.settingsController.syncToggleStates()
    if (this.hasExplorationBoundsValue && this.hasFogToggleTarget)
      this.fogToggleTarget.checked = true

    await this.initializeMap()
    // initializeMap bails without setting this.map if the controller
    // disconnected mid-init (fast Turbo nav); don't build managers on a
    // dead controller with an undefined map. It also returns without a map
    // when the browser refused a WebGL context.
    if (this._disconnected || !this.map) return

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
    // Visits toggle on. When the layer starts enabled by the saved setting,
    // attach it here so panning keeps the dots in sync with the viewport.
    if (this.settings.visitsEnabled) {
      this.visitsManager.attachViewportRefetch()
    }
    this.placesManager = new PlacesManager(this)
    this.placePanel = new PlacePanelBridge(this)
    consumeCreatePlaceLink(this.placesManager)
    this.layerVisibilityManager = new LayerVisibilityManager(this)

    // Listen for tab changes to trigger timeline feed loading via Turbo Frame
    this.boundHandleTabChanged = this.handleTabChanged.bind(this)
    this.cleanup.addEventListener(
      document,
      "map-panel:tab-changed",
      this.boundHandleTabChanged,
    )

    this.timelineBridge.connect(this.cleanup)

    this.timelineSegmentHover = new TimelineSegmentHover(this, () =>
      SettingsManager.getSetting("tracksEnabled"),
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

    const [serverStartDate, serverEndDate] = [
      this.startDateValue,
      this.endDateValue,
    ].map((value) => value.split("T")[0])

    // Format initial dates
    this.startDateValue = DateManager.formatDateForAPI(
      new Date(this.startDateValue),
    )
    this.endDateValue = DateManager.formatDateForAPI(
      new Date(this.endDateValue),
    )

    // Snapshot the load-time window so realtime filtering can tell the default
    // "today" view (whose frozen end goes stale across local midnight) apart
    // from an explicitly selected past range.
    const loadEnd = parseTimestamp(this.endDateValue)
    this.defaultDateRange = {
      startValue: this.startDateValue,
      endValue: this.endDateValue,
      startDate: serverStartDate,
      endDate: serverEndDate,
      reachesNow: loadEnd !== null && loadEnd >= Date.now(),
    }

    if (this.settings.placesEnabled) {
      await this.placesManager.initializePlaceTagFilters({
        reloadPlaces: false,
      })
    }

    this.loadMapData({ fitBounds: !this.hasExplorationBoundsValue }).then(
      () => {
        if (this.hasExplorationBoundsValue) {
          this.map.fitBounds(this.explorationBoundsValue, {
            padding: 70,
            maxZoom: 13,
            duration: 0,
          })
        }
        if (this.settings?.familyEnabled) {
          this.loadFamilyMembers()
        }
        if (anomaliesVisible(SettingsManager.getSettings())) {
          this.layerVisibilityManager.refreshAnomalies({ enabled: true })
        }
      },
    )

    // Show family members list immediately (doesn't depend on layer)
    if (this.settings?.familyEnabled && this.hasFamilyMembersListTarget) {
      this.familyMembersListTarget.style.display = "block"
    }
  }

  disconnect() {
    this._disconnected = true
    this.rangeStatistics?.destroy()
    this.familyManager?.disconnect()
    this.placePanel?.destroy()
    this.replayPanel?.destroy()
    this.settingsController?.stopRecalculationPolling()
    this.searchManager?.destroy()
    this.visitsManager?.destroy()
    this.timelineSegmentHover?.destroy()
    this.eventHandlers?.destroy()
    cancelAllPreviews()
    if (this._persistView) this.map?.off("moveend", this._persistView)
    this.cleanup?.cleanup()
    this.layerManager?.clearLayerReferences()
    this.map?.remove()
    performanceMonitor.logReport()
  }

  isWebGLSupported() {
    try {
      const canvas = document.createElement("canvas")
      const gl = canvas.getContext("webgl2")
      // Hand the probe's context back at once: iOS caps live WebGL contexts,
      // and this one would otherwise linger until GC on every day switch.
      gl?.getExtension("WEBGL_lose_context")?.loseContext()
      return !!gl
    } catch {
      return false
    }
  }

  showWebGLError() {
    this.containerTarget.classList.add("hidden")
    this.webglErrorTarget.classList.remove("hidden")
  }

  async loadViewSettings() {
    await this.settingsController.loadSettings()
    // A city card opens the map with fog on for this view only; the copy
    // keeps the forced layer out of the stored settings.
    this.settings = this.hasExplorationBoundsValue
      ? { ...this.settingsController.settings, fogEnabled: true }
      : this.settingsController.settings
    this.settings.timezone = this.timezoneValue
  }

  async initializeMap() {
    syncSidebarLayout(this.settingsPanelTarget, this.containerTarget, true)
    // Reopen at the user's last viewport instead of the zoomed-out globe.
    // When the date range has data, fitBounds overrides this; when it has
    // none, the map stays on the last-known view rather than the world.
    const lastView = loadLastView(this.apiKeyValue)

    let map
    try {
      map = await MapInitializer.initialize(
        this.containerTarget,
        {
          mapStyle: this.settings.mapStyle,
          globeProjection: this.settings.globeProjection,
          hiddenTileCategories: this.settings.hiddenTileCategories || [],
          disabledPoiGroups: this.settings.disabledPoiGroups || [],
          customTheme: this.settings.customTheme,
          vectorTilesUrl: this.settings.vectorTilesUrl,
          tilesFallback: this.settings.tilesFallback === true,
          ...(lastView ? { center: lastView.center, zoom: lastView.zoom } : {}),
        },
        this.apiKeyValue,
      )
    } catch (error) {
      // The isWebGLSupported() probe passes, yet the browser can still refuse
      // the map its own context, e.g. iOS Safari past its WebGL context limit.
      if (error?.name !== "GPUInitializationError") throw error
      console.warn("[Maps V2] WebGL context refused:", error)
      this.showWebGLError()
      return
    }

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
    const statistics = this.element.querySelector(
      '[data-testid="map-range-statistics"]',
    )
    if (statistics)
      this.rangeStatistics = new RangeStatistics(statistics, this.api)
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
    this.rangeStatistics?.setUnit(this.settings?.distance_unit || "km")
    this.rangeStatistics?.load(this.startDateValue, this.endDateValue)
    return this.mapDataManager.loadMapData(
      this.startDateValue,
      this.endDateValue,
      {
        ...options,
        fitBounds: options.fitBounds !== false && !this.placePanel?.isOpen,
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

    this.layerManager.getLayer("map-editor")?.close()
    this.timelineBridge.clearDayHighlight()
    this.loadMapData()
    this.refreshTimelineFeedIfActive()
    this.familyManager.debouncedLoadHistory()
  }

  /**
   * Timeline panel requested a new day (SPA navigation — no page reload).
   * Mirrors `monthChanged` exactly, including the date format: the Points/Tracks
   * API expects `DateManager.formatDateForAPI`'s local `YYYY-MM-DDTHH:MM+OFFSET`
   * shape. Using `Date#toISOString()` (UTC `Z` suffix) here was causing Tracks
   * to come back empty because the server parsed the dates differently.
   */
  handleTimelineDateNavigated(event) {
    const navigation = this.navigateTimelineDateRange(event.detail || {})
    if (typeof event.detail?.waitUntil === "function") {
      event.detail.waitUntil(navigation)
    } else {
      navigation.catch((error) => console.error(error))
    }
  }

  async navigateTimelineDateRange({ startAt, endAt, fitBounds = true }) {
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

    this.layerManager.getLayer("map-editor")?.close()
    this.timelineBridge.clearDayHighlight()
    await this.loadMapData({ fitBounds })
    if (anomaliesVisible(SettingsManager.getSettings())) {
      this.layerVisibilityManager.refreshAnomalies({ enabled: true })
    }
    this.refreshTimelineFeedIfActive?.()
    this.familyManager.debouncedLoadHistory()
  }

  /**
   * The active window realtime points are filtered against. When the range is
   * still the untouched load-time window that reached the present, the end is
   * left open so live points recorded after local midnight keep showing.
   */
  realtimeDateRange() {
    const startValue = this.startDateValue
    const endValue = this.endDateValue
    const unchanged =
      this.defaultDateRange &&
      startValue === this.defaultDateRange.startValue &&
      endValue === this.defaultDateRange.endValue

    return {
      startValue,
      endValue,
      treatEndAsOpen: Boolean(unchanged && this.defaultDateRange.reachesNow),
    }
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
      this.progressBadgeTextTarget.textContent = translate("common.loading")
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
      parts.push(
        translate(`loading_sources.${source}`, {
          count,
          formatted_count: formatNumber(count),
        }),
      )
    }

    // Append family count if family layer is enabled
    if (this.settings?.familyEnabled && counts.family === undefined) {
      const familyCount = this.familyManager.memberCount
      parts.push(
        translate("loading_sources.family", {
          count: familyCount,
          formatted_count: formatNumber(familyCount),
        }),
      )
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
      parts.length > 0 ? parts.join(" \u00B7 ") : translate("common.loading")

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
      if (isOpening) {
        this.settingsPanelTrigger = document.activeElement
      } else if (this.settingsPanelTarget.contains(document.activeElement)) {
        const trigger = this.settingsPanelTrigger?.isConnected
          ? this.settingsPanelTrigger
          : document.querySelector('[data-testid="map-button-timeline"]')
        trigger?.focus()
      }
      this.settingsPanelTarget.inert = !isOpening
      this.settingsPanelTarget.classList.toggle("open")

      // Shrink/expand map container
      if (this.hasContainerTarget) {
        if (!isOpening) {
          this.settingsPanelTarget.classList.remove("timeline-expanded")
          // Cluster doubles as the panel's tab strip — clear its active
          // state when the panel is dismissed (e.g. via the header X) so
          // users don't see a button still highlighted with no panel open.
          document.dispatchEvent(new CustomEvent("map-panel:closed"))
        }
        syncSidebarLayout(this.settingsPanelTarget, this.containerTarget)
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
    } else if (this.timelineBridge.highlightedDay) {
      // Leaving timeline-feed tab — restore full opacity
      this.timelineBridge.clearDayHighlight()
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
  updateTilesFallback(event) {
    return this.settingsController.updateTilesFallback(event)
  }
  updateTrackColor(event) {
    return this.settingsController.updateTrackColor(event)
  }
  toggleSpeedColoredRoutes(event) {
    return this.settingsController.toggleSpeedColoredRoutes(event)
  }
  updateSpeedColorScale(event) {
    return this.settingsController.updateSpeedColorScale(event)
  }
  resetLayerColors() {
    return this.settingsController.resetLayerColors()
  }
  updateAdvancedSettings(event) {
    return this.settingsController.updateAdvancedSettings(event)
  }
  updateGpsAccuracyThresholdDisplay(event) {
    return this.settingsController.updateGpsAccuracyThresholdDisplay(event)
  }
  updateMinMinutesInCityDisplay(event) {
    return this.settingsController.updateMinMinutesInCityDisplay(event)
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
  toggleArchivedPlaces(event) {
    return this.placesManager.toggleArchivedPlaces(event)
  }
  togglePlaceBoundaries(event) {
    return this.placesManager.togglePlaceBoundaries(event)
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

  // Routes Manager methods
  togglePoints(event) {
    return this.layerVisibilityManager.togglePoints(event)
  }

  togglePointsEditing(event) {
    return this.settingsController.togglePointsEditing(event)
  }

  toggleHeatmap(event) {
    return this.layerVisibilityManager.toggleHeatmap(event)
  }
  toggleHexagons(event) {
    return this.layerVisibilityManager.toggleHexagons(event)
  }
  toggleFog(event) {
    return this.layerVisibilityManager.toggleFog(event)
  }
  toggleScratch(event) {
    return this.layerVisibilityManager.toggleScratch(event)
  }
  async togglePhotos(event) {
    await this.layerVisibilityManager.togglePhotos(event)
    if (!this.replayPanel?.isOpen) return
    if (!event.target.checked) this._photosWasVisible = false
    this.replayPanel.refreshReplayPhotos()
  }
  toggleTracks(event) {
    return this.layerVisibilityManager.toggleTracks(event)
  }
  toggleFlights(event) {
    return this.layerVisibilityManager.toggleFlights(event)
  }
  toggleAnomalies(event) {
    return this.layerVisibilityManager.toggleAnomalies(event)
  }
  toggleFamily(event) {
    return this.layerVisibilityManager.toggleFamily(event)
  }

  loadFamilyMembers() {
    return this.familyManager.loadMembers()
  }

  centerOnFamilyMember(event) {
    return this.familyManager.centerOnMember(event)
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
              action.handler === "handleDelete"
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

  closeInfo(options = {}) {
    if (!this.hasInfoDisplayTarget) return
    this.infoDisplayTarget.classList.add("hidden")

    if (options.clearSelection !== false && this.eventHandlers) {
      this.eventHandlers.clearTrackSelection()
      this.eventHandlers.clearPointSelection()
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
      case "point":
        this.deletePoint(id)
        break
      case "place":
        return deletePlace(this, id)
      default:
        console.warn("[Maps V2] Unknown entity type for delete:", entityType)
    }
  }

  /** Delete a point, then invalidate the tile-backed presentation. */
  async deletePoint(pointId) {
    const confirmed = confirm(translate("map.confirm_delete_point_permanently"))
    if (!confirmed) return

    try {
      await this.api.deletePoint(pointId)
      this.mapDataManager?.invalidatePoints()
      this.layerManager.getLayer("map-editor")?.close()
      this.layerManager.getLayer("points-mvt")?.refresh()
      this.layerManager.getLayer("tracks-mvt")?.refresh()
      this.layerManager
        .getLayer("scratch")
        ?.update()
        .catch(() => {})
      this.closeInfo()
      Toast.success(translate("messages.point_deleted_successfully"))
    } catch (_error) {
      Toast.error(translate("messages.failed_to_delete_point"))
    }
  }

  /** Mark an anomaly as correct, then reload anomalies, points and tracks. */
  async markPointValid(event) {
    try {
      await this.api.markPointValid(event.currentTarget.dataset.id)
      this.mapDataManager?.invalidatePoints()
      this.layerManager.getLayer("points-mvt")?.refresh()
      this.layerManager.getLayer("tracks-mvt")?.refresh()
      this.layerVisibilityManager.refreshAnomalies({ enabled: true })
      this.closeInfo()
      Toast.success(translate("messages.point_marked_valid"))
    } catch (_error) {
      Toast.error(translate("messages.failed_to_mark_point_valid"))
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
    return pointsSource?.serialize?.()?.data?.features || []
  }

  _updateTrackReplayButton(playing) {
    const playIcon = document.getElementById("track-replay-play-icon")
    const pauseIcon = document.getElementById("track-replay-pause-icon")
    const label = document.getElementById("track-replay-label")
    if (!playIcon || !pauseIcon || !label) return

    if (playing) {
      playIcon.classList.add("hidden")
      pauseIcon.classList.remove("hidden")
      label.textContent = translate("replay.pause")
    } else {
      playIcon.classList.remove("hidden")
      pauseIcon.classList.add("hidden")
      label.textContent = translate("replay.replay")
    }
  }
}
