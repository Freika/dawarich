import { Controller } from "@hotwired/stimulus"
import { MapInitializer } from "controllers/maps/maplibre/map_initializer"
import { TripRoutesTileLayer } from "maps_maplibre/layers/trip_routes_tile_layer"
import {
  applyDayColors,
  expandAllDays,
  selectDayFromMap,
  toggleDay,
} from "maps_maplibre/trip/day_accordion"
import { applyFlightMask, toggleTripFlights } from "maps_maplibre/trip/flights"
import {
  observePendingPath,
  syncPendingPath,
} from "maps_maplibre/trip/path_sync"
import { toggleTripPhotos } from "maps_maplibre/trip/photos"
import { focusPlanStop, setPlanVisible } from "maps_maplibre/trip/plan_overlay"
import {
  ensureTripPoints,
  openTripStudio,
  tripPosterProvider,
} from "maps_maplibre/trip/points"
import { toggleTripReplay } from "maps_maplibre/trip/replay"

/**
 * Trip MapLibre Controller
 * Renders a MapLibre map for the trip show page with day-colored routes,
 * an accordion-based day navigator, photos overlay, and trip replay.
 */
export default class extends Controller {
  static targets = [
    "map",
    "pathPending",
    "daysAccordion",
    "expandAllBtn",
    "loadingIndicator",
    "posterBtn",
    "videoBtn",
    // Photos button
    "photosToggleBtn",
    // Flights button
    "flightsToggleBtn",
    "planToggleBtn",
    // Replay toggle button
    "replayToggleBtn",
    // Replay panel
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
    "replayPlayButton",
    "replayFollowButton",
    "replayPlayIcon",
    "replayPauseIcon",
    "replaySpeedSlider",
    "replaySpeedLabel",
    "replaySpeedDisplay",
  ]

  static values = {
    apiKey: String,
    timezone: String,
    startedAt: String,
    endedAt: String,
    tripId: Number,
    tripName: String,
    metersBetweenRoutes: { type: Number, default: 500 },
    minutesBetweenRoutes: { type: Number, default: 60 },
    tilesUrl: String,
    dayKeys: Array,
    dayBounds: Object,
    dayEndpoints: Object,
    fullBounds: Array,
    deviceWindows: Array,
    plan: String,
    mapStyle: { type: String, default: "light" },
  }

  async connect() {
    this.selectedDay = null
    this.dayRoutesLayer = null
    this.dayRouteCollections = []
    this.pointsPromise = null
    this.photosLayer = null
    this.photosGeoJSON = null
    this.photosActive = false
    this.flightsLayer = null
    this.flightsGeoJSON = null
    this.flightsActive = false
    this.planLayer = null
    this.allPoints = []
    this.replayPanel = null

    this.onPlanFocus = (event) => focusPlanStop(this, event.detail || {})
    window.addEventListener("trip-plan:focus", this.onPlanFocus)

    if (this.hasPathPendingTarget) {
      this.pathObserver = observePendingPath(this)
    }

    if (this.hasMapTarget) {
      await this.initializeMap()
    }
  }

  disconnect() {
    this.pathObserver?.disconnect()
    window.removeEventListener("trip-plan:focus", this.onPlanFocus)
    this.planLayer?.remove()
    this.planLayer = null
    this.replayPanel?.destroy()
    if (this.photosLayer) {
      this.photosLayer.remove()
      this.photosLayer = null
    }
    if (this.flightsLayer) {
      this.flightsLayer.remove()
      this.flightsLayer = null
    }
    if (this.dayRoutesLayer) {
      this.dayRoutesLayer.remove()
    }
    if (this.map) {
      this.map.remove()
      this.map = null
    }
    this.mapInitializing = false
  }

  syncPendingPath() {
    return syncPendingPath(this)
  }

  async mapTargetConnected() {
    if (!this.map && !this.mapInitializing) {
      await this.initializeMap()
    }
  }

  async initializeMap() {
    if (!this.hasMapTarget || this.mapInitializing) return
    this.mapInitializing = true

    this.map = await MapInitializer.initialize(
      this.mapTarget,
      {
        mapStyle: this.mapStyleValue,
        center: [0, 0],
        zoom: 2,
        showControls: true,
      },
      this.apiKeyValue,
    )

    this.map.on("load", () => this.addTripRoutes())
  }

  addTripRoutes() {
    this.dayRoutesLayer = new TripRoutesTileLayer(this.map, {
      tilesUrl: this.tilesUrlValue,
      dayKeys: this.dayKeysValue,
      dayBounds: this.dayBoundsValue,
      fullBounds: this.fullBoundsValue,
      dayEndpoints: this.dayEndpointsValue,
    })
    applyDayColors(this, this.dayRoutesLayer.getDayKeys())
    this.dayRoutesLayer.setupInteractions({
      onDayClick: (dayKey) => selectDayFromMap(this, dayKey),
    })
    this.fitFullBounds()
    if (this.flightsActive) applyFlightMask(this)
  }

  fitFullBounds() {
    const fullBounds = this.dayRoutesLayer?.getFullBounds()
    if (fullBounds) {
      this.map.fitBounds(fullBounds, { padding: 50, maxZoom: 15 })
    }
  }

  ensurePoints() {
    return ensureTripPoints(this)
  }

  toggleDay(event) {
    toggleDay(this, event)
  }

  expandAllDays() {
    expandAllDays(this)
  }

  showLoading(show) {
    if (this.hasLoadingIndicatorTarget) {
      this.loadingIndicatorTarget.classList.toggle("hidden", !show)
    }
  }

  // ===== Poster and video studios =====

  openPosterStudio() {
    return openTripStudio(this, "poster-studio:open")
  }

  openVideoStudio() {
    return openTripStudio(this, "video-studio:open")
  }

  posterProvider() {
    return tripPosterProvider(this)
  }

  // ===== Map overlays =====

  togglePhotos() {
    return toggleTripPhotos(this)
  }

  toggleFlights() {
    return toggleTripFlights(this)
  }

  togglePlan() {
    setPlanVisible(this, !this.planLayer)
  }

  // ===== Note form toggling =====

  showNoteForm(event) {
    this.toggleNoteVisibility(event.currentTarget.dataset.date, true)
  }

  hideNoteForm(event) {
    this.toggleNoteVisibility(event.currentTarget.dataset.date, false)
  }

  toggleNoteVisibility(date, showForm) {
    const display = this.element.querySelector(`[data-note-display="${date}"]`)
    const form = this.element.querySelector(`[data-note-form="${date}"]`)
    if (display) display.classList.toggle("hidden", showForm)
    if (form) form.classList.toggle("hidden", !showForm)
  }

  // ===== Replay (delegates to the reusable ReplayPanel) =====

  toggleReplay() {
    return toggleTripReplay(this)
  }

  replayScrubberHover(event) {
    this.replayPanel?.scrubberHover(event)
  }

  replayPrevDay() {
    this.replayPanel?.prevDay()
  }

  replayNextDay() {
    this.replayPanel?.nextDay()
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
}
