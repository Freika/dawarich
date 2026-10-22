import { Controller } from "@hotwired/stimulus"
import { MapInitializer } from "controllers/maps/maplibre/map_initializer"
import { translate } from "i18n"
import { FlightsLayer } from "maps_maplibre/layers/flights_layer"
import { PhotosLayer } from "maps_maplibre/layers/photos_layer"
import { TripPlanLayer } from "maps_maplibre/layers/trip_plan_layer"
import { TripRoutesTileLayer } from "maps_maplibre/layers/trip_routes_tile_layer"
import { ReplayManager } from "maps_maplibre/managers/replay_manager"
import { ReplayPanel } from "maps_maplibre/managers/replay_panel"
import { ApiClient } from "maps_maplibre/services/api_client"
import { buildDayRouteCollections } from "maps_maplibre/utils/day_route_collections"
import { pointsFromDevice } from "maps_maplibre/utils/device_points"
import { featureToPhoto } from "maps_maplibre/utils/feature_to_photo"
import { flightWindows, maskLines } from "maps_maplibre/utils/flight_mask"
import { buildTripGeojson, TripProvider } from "poster_studio/data/providers"
import Flash from "./flash_controller"

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

    this.onPlanFocus = (event) => this.focusPlanStop(event.detail || {})
    window.addEventListener("trip-plan:focus", this.onPlanFocus)

    if (this.hasPathPendingTarget) {
      // Recover path updates broadcast before the stream subscribes or reconnects.
      const sources = document.querySelectorAll("turbo-cable-stream-source")
      this.pathObserver = new MutationObserver((mutations) => {
        if (mutations.some(({ target }) => target.hasAttribute("connected"))) {
          this.syncPendingPath()
        }
      })
      sources.forEach((source) => {
        this.pathObserver.observe(source, {
          attributes: true,
          attributeFilter: ["connected"],
        })
      })
      if ([...sources].some((source) => source.hasAttribute("connected"))) {
        this.syncPendingPath()
      }
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

  async syncPendingPath() {
    if (!this.hasPathPendingTarget) return
    // A request made mid-fetch may follow a newer path save, so rerun once.
    if (this.syncingPath) {
      this.pathSyncQueued = true
      return
    }

    this.syncingPath = true
    try {
      const response = await fetch(window.location.href, {
        headers: { Accept: "text/html" },
        credentials: "same-origin",
      })
      if (!response.ok)
        throw new Error(`Trip path sync failed: ${response.status}`)

      const latest = new DOMParser().parseFromString(
        await response.text(),
        "text/html",
      )
      if (
        this.element.isConnected &&
        this.hasPathPendingTarget &&
        latest.querySelector('[data-trip-maplibre-target="map"]')
      ) {
        Turbo.visit(window.location.href, { action: "replace" })
      }
    } catch (error) {
      console.warn("Could not synchronize trip path", error)
    } finally {
      this.syncingPath = false
      if (this.pathSyncQueued) {
        this.pathSyncQueued = false
        this.syncPendingPath()
      }
    }
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
    this.applyDayColors(this.dayRoutesLayer.getDayKeys())
    this.dayRoutesLayer.setupInteractions({
      onDayClick: (dayKey) => this.selectDayFromMap(dayKey),
    })
    this.fitFullBounds()
    if (this.flightsActive) this.applyFlightMask()
  }

  fitFullBounds() {
    const fullBounds = this.dayRoutesLayer?.getFullBounds()
    if (fullBounds) {
      this.map.fitBounds(fullBounds, { padding: 50, maxZoom: 15 })
    }
  }

  ensurePoints() {
    this.pointsPromise ||= this.loadPoints().catch((error) => {
      this.pointsPromise = null
      throw error
    })
    return this.pointsPromise
  }

  async loadPoints() {
    this.setPointsLoading(true)
    try {
      const { points } = await new ApiClient(this.apiKeyValue).fetchAllPoints({
        start_at: this.startedAtValue,
        end_at: this.endedAtValue,
      })
      const allPoints = pointsFromDevice(points || [], this.deviceWindowsValue)
      const grouper = new ReplayManager({ timezone: this.timezoneValue })
      grouper.setPoints(allPoints)
      const pointsByDay = {}
      for (const dayKey of grouper.availableDays) {
        pointsByDay[dayKey] = grouper.getPointsForDay(dayKey)
      }

      this.allPoints = allPoints
      this.dayRouteCollections = buildDayRouteCollections(pointsByDay, {
        distanceThresholdMeters: this.metersBetweenRoutesValue,
        timeThresholdMinutes: this.minutesBetweenRoutesValue,
      })
      return allPoints
    } finally {
      this.setPointsLoading(false)
    }
  }

  setPointsLoading(loading) {
    this.showLoading(loading)
    if (loading) {
      this.busyButtons = ["posterBtn", "videoBtn", "replayToggleBtn"]
        .filter(
          (name) => this[`has${name[0].toUpperCase()}${name.slice(1)}Target`],
        )
        .map((name) => this[`${name}Target`])
        .filter((button) => !button.disabled)
    }
    for (const button of this.busyButtons || []) {
      button.disabled = loading
      if (loading) button.setAttribute("aria-busy", "true")
      else button.removeAttribute("aria-busy")
    }
  }

  applyDayColors(dayKeys) {
    if (!this.hasDaysAccordionTarget) return

    for (const dayKey of dayKeys) {
      const color = this.dayRoutesLayer.getDayColor(dayKey)
      const dot = this.daysAccordionTarget.querySelector(
        `[data-day-dot="${dayKey}"]`,
      )
      if (dot && color) {
        dot.style.backgroundColor = color
      }
    }
  }

  selectDayFromMap(dayKey) {
    if (!this.hasDaysAccordionTarget) return

    const allDetails = this.daysAccordionTarget.querySelectorAll(
      "details[data-day-key]",
    )
    const target = this.daysAccordionTarget.querySelector(
      `details[data-day-key="${dayKey}"]`,
    )
    if (!target) return

    for (const d of allDetails) {
      if (d !== target) {
        d.removeAttribute("open")
      }
    }
    target.setAttribute("open", "")

    this.selectedDay = dayKey

    if (this.dayRoutesLayer) {
      this.dayRoutesLayer.selectDay(dayKey)

      const dayBounds = this.dayRoutesLayer.getDayBounds(dayKey)
      if (dayBounds) {
        this.map.fitBounds(dayBounds, { padding: 50, maxZoom: 15 })
      }
    }

    target.scrollIntoView({ behavior: "smooth", block: "nearest" })

    this.replayPanel?.syncToDay(dayKey)
  }

  toggleDay(event) {
    event.preventDefault()

    const summary = event.currentTarget
    const details = summary.closest("details")
    const dayKey = summary.dataset.tripMaplibreDayKeyParam
    if (!details || !dayKey) return

    if (details.open) {
      details.removeAttribute("open")
      this.selectedDay = null

      if (this.dayRoutesLayer) {
        this.dayRoutesLayer.selectAllDays()

        this.fitFullBounds()
      }
    } else {
      const allDetails = this.daysAccordionTarget.querySelectorAll(
        "details[data-day-key]",
      )
      for (const d of allDetails) {
        if (d !== details) {
          d.removeAttribute("open")
        }
      }
      details.setAttribute("open", "")

      this.selectedDay = dayKey

      if (this.dayRoutesLayer) {
        this.dayRoutesLayer.selectDay(dayKey)

        const dayBounds = this.dayRoutesLayer.getDayBounds(dayKey)
        if (dayBounds) {
          this.map.fitBounds(dayBounds, { padding: 50, maxZoom: 15 })
        }
      }

      this.replayPanel?.syncToDay(dayKey)
    }
  }

  expandAllDays() {
    if (!this.hasDaysAccordionTarget) return

    const allDetails = this.daysAccordionTarget.querySelectorAll(
      "details[data-day-key]",
    )
    const allOpen = Array.from(allDetails).every((d) => d.hasAttribute("open"))

    if (allOpen) {
      for (const d of allDetails) {
        d.removeAttribute("open")
      }
      if (this.hasExpandAllBtnTarget) {
        this.expandAllBtnTarget.textContent = translate("trip.show_all_days")
      }
    } else {
      for (const d of allDetails) {
        d.setAttribute("open", "")
      }
      if (this.hasExpandAllBtnTarget) {
        this.expandAllBtnTarget.textContent = translate(
          "trip.collapse_all_days",
        )
      }
    }

    this.selectedDay = null

    if (this.dayRoutesLayer) {
      this.dayRoutesLayer.selectAllDays()

      this.fitFullBounds()
    }
  }

  showLoading(show) {
    if (this.hasLoadingIndicatorTarget) {
      this.loadingIndicatorTarget.classList.toggle("hidden", !show)
    }
  }

  // ===== Poster studio =====

  openPosterStudio() {
    return this.openStudio("poster-studio:open")
  }

  async openStudio(eventName) {
    try {
      await this.ensurePoints()
    } catch (error) {
      console.error("[TripMapLibre] Error fetching points:", error)
      Flash.show(
        "error",
        translate("messages.failed_to_load_location_data_please_try_again"),
      )
      return
    }
    if (!this.element.isConnected) return

    document.dispatchEvent(
      new CustomEvent(eventName, {
        detail: { provider: this.posterProvider() },
      }),
    )
  }

  posterProvider() {
    const geojson = this.posterGeojson()
    // Keep the GPS snapshot for video, including switches between studios.
    const posterGeojson =
      this.flightsActive && this.flightsLayer?.visible
        ? {
            type: "FeatureCollection",
            features: [
              ...maskLines(geojson, flightWindows(this.flightsGeoJSON))
                .features,
              ...(this.flightsLayer.data?.features ?? []),
            ],
          }
        : geojson
    return new TripProvider({
      geojson,
      posterGeojson,
      startAt: this.startedAtValue,
      endAt: this.endedAtValue,
      title: this.tripNameValue,
      points: this.allPoints,
      timezone: this.timezoneValue,
    })
  }

  // ===== Video studio =====

  openVideoStudio() {
    return this.openStudio("video-studio:open")
  }

  posterGeojson() {
    return buildTripGeojson({ dayRouteCollections: this.dayRouteCollections })
  }

  // ===== Photos layer toggle (button-based) =====

  async togglePhotos() {
    this.photosActive = !this.photosActive

    if (!this.photosActive) {
      if (this.photosLayer) {
        this.photosLayer.remove()
        this.photosLayer = null
      }
      this._setButtonActive(this.photosToggleBtnTarget, false)
      if (this.replayPanel?.isOpen) this.replayPanel.refreshReplayPhotos()
      return
    }

    if (!this.photosGeoJSON) {
      const apiClient = new ApiClient(this.apiKeyValue)
      try {
        const photos = await apiClient.fetchPhotos({
          start_at: this.startedAtValue,
          end_at: this.endedAtValue,
        })
        this.photosGeoJSON = this.photosToGeoJSON(photos)
      } catch (e) {
        console.error("[TripMapLibre] Error fetching photos:", e)
        this.photosActive = false
        return
      }
    }

    if (this.photosGeoJSON.features.length === 0) {
      this.photosActive = false
      return
    }

    this.photosLayer = new PhotosLayer(this.map)
    this.photosLayer.add(this.photosGeoJSON)
    this._setButtonActive(this.photosToggleBtnTarget, true)
    if (this.replayPanel?.isOpen) this.replayPanel.refreshReplayPhotos()
  }

  photosToGeoJSON(photos) {
    return {
      type: "FeatureCollection",
      features: photos.map((photo) => {
        const thumbnailUrl = `/api/v1/photos/${photo.id}/thumbnail.jpg?api_key=${this.apiKeyValue}&source=${photo.source}`
        return {
          type: "Feature",
          geometry: {
            type: "Point",
            coordinates: [photo.longitude, photo.latitude],
          },
          properties: {
            id: photo.id,
            thumbnail_url: thumbnailUrl,
            taken_at: photo.capturedAt || photo.localDateTime,
            filename: photo.originalFileName,
            city: photo.city,
            state: photo.state,
            country: photo.country,
            type: photo.type,
            source: photo.source,
          },
        }
      }),
    }
  }

  // ===== Flights layer toggle (button-based) =====

  async toggleFlights() {
    this.flightsActive = !this.flightsActive

    if (!this.flightsActive) {
      this.flightsLayer?.hide()
      this.applyFlightMask()
      this._setButtonActive(this.flightsToggleBtnTarget, false)
      return
    }

    if (!this.flightsGeoJSON) {
      const apiClient = new ApiClient(this.apiKeyValue)
      try {
        this.flightsGeoJSON = await apiClient.fetchFlights({
          start_at: this.startedAtValue,
          end_at: this.endedAtValue,
        })
      } catch (e) {
        console.error("[TripMapLibre] Error fetching flights:", e)
        // Drop the cache so the next click retries the fetch.
        this.flightsGeoJSON = null
        this.flightsActive = false
        this._setButtonActive(this.flightsToggleBtnTarget, false)
        Flash.show(
          "error",
          translate("messages.could_not_load_flights_please_try_again"),
        )
        return
      }
    }

    if (!this.flightsGeoJSON.features?.length) {
      // Drop the cache so flights added to AirTrail later in the session are
      // picked up on the next click instead of staying empty.
      this.flightsGeoJSON = null
      this.flightsActive = false
      this._setButtonActive(this.flightsToggleBtnTarget, false)
      Flash.show("notice", translate("messages.no_flights_found_for_this_trip"))
      return
    }

    if (!this.flightsLayer) {
      this.flightsLayer = new FlightsLayer(this.map, {
        style: this.mapStyleValue,
      })
      this.flightsLayer.add(this.flightsGeoJSON)
    } else {
      this.flightsLayer.update(this.flightsGeoJSON)
      this.flightsLayer.show()
    }

    this.applyFlightMask()
    this._setButtonActive(this.flightsToggleBtnTarget, true)
  }

  applyFlightMask() {
    const tripStart = Date.parse(this.startedAtValue) / 1000
    const tripEnd = Date.parse(this.endedAtValue) / 1000
    const windows =
      this.flightsActive && this.flightsLayer?.visible
        ? flightWindows(this.flightsGeoJSON).filter(
            ([from, to]) => to >= tripStart && from <= tripEnd,
          )
        : []
    this.dayRoutesLayer?.setExcludedWindows(windows)
  }

  // ===== Planned itinerary overlay =====

  togglePlan() {
    this.setPlanVisible(!this.planLayer)
  }

  setPlanVisible(visible) {
    if (!this.map || !this.planValue) return

    if (visible) {
      let plan
      try {
        plan = JSON.parse(this.planValue)
      } catch (_e) {
        return
      }
      this.planLayer = new TripPlanLayer(this.map, { numbered: true })
      this.planLayer.add(plan)
    } else {
      this.planLayer?.remove()
      this.planLayer = null
    }

    if (this.hasPlanToggleBtnTarget) {
      this._setButtonActive(this.planToggleBtnTarget, visible)
      this.planToggleBtnTarget.setAttribute("aria-pressed", String(visible))
    }
  }

  focusPlanStop({ longitude, latitude }) {
    if (!Number.isFinite(longitude) || !Number.isFinite(latitude)) return
    if (!this.planLayer) this.setPlanVisible(true)
    this.planLayer?.focus(longitude, latitude)
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

  async toggleReplay() {
    if (!this.hasReplayPanelTarget || this.replayToggling) return
    if (!this.replayPanel) {
      this.replayPanel = new ReplayPanel({
        controller: this,
        map: this.map,
        dayRoutesLayer: this.dayRoutesLayer,
        element: this.element,
        timezone: this.timezoneValue,
        loadPoints: async () => {
          const points = await this.ensurePoints()
          return this.element.isConnected ? points : []
        },
        getPhotos: () =>
          this.photosActive && this.photosGeoJSON
            ? this.photosGeoJSON.features.map(featureToPhoto)
            : [],
        onReplayPhotosActive: (active) => {
          if (!this.photosLayer) return
          if (active) {
            this._photosWasVisible = this.photosLayer.visible
            this.photosLayer.hide()
          } else if (this._photosWasVisible) {
            this.photosLayer.show()
          }
        },
      })
    }
    this.replayToggling = true
    try {
      await this.replayPanel.toggle()
    } catch (error) {
      console.error("[TripMapLibre] Error fetching points:", error)
      Flash.show(
        "error",
        translate("messages.failed_to_load_location_data_please_try_again"),
      )
    } finally {
      this.replayToggling = false
    }
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

  // --- Button active state helper ---

  _setButtonActive(button, active) {
    if (!button) return
    if (active) {
      button.classList.remove("btn-outline")
      button.classList.add("btn-active", "btn-primary")
    } else {
      button.classList.remove("btn-active", "btn-primary")
      button.classList.add("btn-outline")
    }
  }
}
