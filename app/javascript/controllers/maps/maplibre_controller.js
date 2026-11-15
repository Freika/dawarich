import { Controller } from "@hotwired/stimulus"
import { translate } from "i18n"
import { Toast } from "maps_maplibre/components/toast"
import { CleanupHelper } from "maps_maplibre/utils/cleanup_helper"
import { anomaliesVisible } from "maps_maplibre/utils/layer_dependencies"
import { cancelAllPreviews } from "maps_maplibre/utils/layer_gate"
import { performanceMonitor } from "maps_maplibre/utils/performance_monitor"
import { SettingsManager } from "maps_maplibre/utils/settings_manager"
import { syncSidebarLayout } from "maps_maplibre/utils/sidebar_layout"
import { setPrivacyZonesFingerprint } from "maps_maplibre/utils/tile_freshness"
import { MapDateRange } from "./maplibre/date_range"
import { FamilyManager } from "./maplibre/family_manager"
import { InfoPanel } from "./maplibre/info_panel"
import { LoadingBadge } from "./maplibre/loading_badge"
import { buildMapFeatures, listenToDocument } from "./maplibre/map_bootstrap"
import { MapReplayActions } from "./maplibre/map_replay"
import {
  initializeMap,
  isWebGLSupported,
  loadViewSettings,
  showWebGLError,
} from "./maplibre/map_startup"
import { SettingsController } from "./maplibre/settings_manager"
import { TimelineMapBridge } from "./maplibre/timeline_map_bridge"

/**
 * Main map controller for Maps V2
 * Coordinates between different managers and handles UI interactions
 */
export default class MapController extends Controller {
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
    "notesToggle",
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
    // Replay panel. Not inherited from ReplayHost: the protected
    // spec/regressions harnesses load this file with only a bare Controller.
    "replayPanel",
    "replayScrubber",
    "replayScrubberTrack",
    "replayDensityContainer",
    "replayDaySegments",
    "replayDayDisplay",
    "replayDayCount",
    "replayTimeDisplay",
    "replayDataIndicator",
    "replayCycleControls",
    "replayPointCounter",
    "replayPlayButton",
    "replayFollowButton",
    "replayPlayIcon",
    "replayPauseIcon",
    "replaySpeedSlider",
    "replaySpeedLabel",
    "replaySpeedDisplay",
    // Timeline feed
    "timelineFeedContainer",
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

    if (!isWebGLSupported()) {
      showWebGLError(this)
      return
    }

    this.cleanup = new CleanupHelper()
    setPrivacyZonesFingerprint(this.privacyZonesFingerprintValue)

    // Initialize API and settings
    SettingsManager.initialize(this.apiKeyValue)
    this.familyManager = new FamilyManager(this)
    this.loadingBadge = new LoadingBadge(this)
    this.infoPanel = new InfoPanel(this)
    this.dateRange = new MapDateRange(this)
    this.replayActions = new MapReplayActions(this)
    this.timelineBridge = new TimelineMapBridge(this)
    this.settingsController = new SettingsController(this)
    await loadViewSettings(this)

    // Sync toggle states with loaded settings
    this.settingsController.syncToggleStates()
    if (this.hasExplorationBoundsValue && this.hasFogToggleTarget)
      this.fogToggleTarget.checked = true

    await initializeMap(this)
    // initializeMap bails without setting this.map if the controller
    // disconnected mid-init (fast Turbo nav); don't build managers on a
    // dead controller with an undefined map. It also returns without a map
    // when the browser refused a WebGL context.
    if (this._disconnected || !this.map) return

    buildMapFeatures(this)
    listenToDocument(this)
    this.dateRange.snapshotInitial()

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
    this.searchManager?.destroy()
    this.visitsManager?.destroy()
    this.notesManager?.destroy()
    this.timelineSegmentHover?.destroy()
    this.eventHandlers?.destroy()
    cancelAllPreviews()
    if (this._persistView) this.map?.off("moveend", this._persistView)
    this.cleanup?.cleanup()
    this.layerManager?.clearLayerReferences()
    this.map?.remove()
    performanceMonitor.logReport()
  }

  /**
   * Load map data from API
   */
  async loadMapData(options = {}) {
    this.rangeStatistics?.setUnit(this.settings?.distance_unit || "km")
    this.rangeStatistics?.load(this.startDateValue, this.endDateValue)
    this.notesManager?.reload()
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

  async togglePhotos(event) {
    await this.layerVisibilityManager.togglePhotos(event)
    if (!this.replayPanel?.isOpen) return
    if (!event.target.checked) this._photosWasVisible = false
    this.replayPanel.refreshReplayPhotos()
  }

  loadFamilyMembers() {
    return this.familyManager.loadMembers()
  }

  centerOnFamilyMember(event) {
    return this.familyManager.centerOnMember(event)
  }

  showInfo(title, content, actions = []) {
    return this.infoPanel.show(title, content, actions)
  }

  closeInfo(options = {}) {
    return this.infoPanel?.close(options)
  }

  /** Open the visit edit modal. Called by the private E2E suite. */
  async openVisitModal(visitId) {
    try {
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
      document.dispatchEvent(
        new CustomEvent("visit:edit", { detail: { visit }, bubbles: true }),
      )
    } catch (_error) {
      Toast.error(translate("messages.failed_to_load_visit_details"))
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

  async toggleTrackPoints(event) {
    const target = event?.currentTarget
    if (!target) return
    const trackId = target.dataset.trackId
    if (!trackId) return
    await this.eventHandlers?._toggleTrackPoints(trackId, !!target.checked)
  }

  _getLoadedPoints() {
    if (this.mapDataManager?.lastLoadedData?.points) {
      return this.mapDataManager.lastLoadedData.points
    }

    const pointsSource = this.map?.getSource("points-source")
    return pointsSource?.serialize?.()?.data?.features || []
  }
}

/**
 * Actions the views bind (and the private E2E suite calls) that only forward
 * to the manager owning them: { "path.from.controller": [method names] }.
 * The manager is looked up on each call, so it may be built after connect.
 */
const FORWARDED_ACTIONS = {
  "settingsController.style": [
    "updateMapStyle",
    "toggleTileCategory",
    "togglePoiGroup",
    "updateVectorTilesUrl",
    "updateTilesFallback",
    "toggleGlobe",
  ],
  settingsController: [
    "applyMapStyle",
    "resetSettings",
    "updateDistanceUnit",
    "updateTrackColor",
    "toggleSpeedColoredRoutes",
    "updateSpeedColorScale",
    "resetLayerColors",
    "togglePointsEditing",
  ],
  areaSelectionManager: [
    "startSelectArea",
    "cancelAreaSelection",
    "deleteSelectedPoints",
    "deleteSelectedAnomalies",
  ],
  visitsManager: [
    "toggleVisits",
    "searchVisits",
    "filterVisits",
    "startCreateVisit",
  ],
  notesManager: ["toggleNotes", "startCreateNote"],
  placesManager: [
    "togglePlaces",
    "toggleArchivedPlaces",
    "togglePlaceBoundaries",
    "filterPlacesByTags",
    "toggleAllPlaceTags",
    "startCreatePlace",
  ],
  infoPanel: ["handleDelete", "deletePoint", "markPointValid"],
  replayActions: [
    "toggleReplay",
    "replayScrubberHover",
    "replayCyclePrev",
    "replayCycleNext",
    "replayTogglePlayback",
    "replayRecenterFollow",
    "replaySpeedChange",
    "replayTrack",
  ],
  dateRange: [
    "monthChanged",
    "handleTimelineDateNavigated",
    "navigateTimelineDateRange",
    "setDateRange",
    "realtimeDateRange",
  ],
  layerVisibilityManager: [
    "togglePoints",
    "toggleHeatmap",
    "toggleHexagons",
    "toggleFog",
    "toggleScratch",
    "toggleTracks",
    "toggleFlights",
    "toggleAnomalies",
    "toggleFamily",
  ],
}

for (const [path, names] of Object.entries(FORWARDED_ACTIONS)) {
  const keys = path.split(".")
  for (const name of names) {
    MapController.prototype[name] = function (...args) {
      const owner = keys.reduce((object, key) => object[key], this)
      return owner[name](...args)
    }
  }
}
