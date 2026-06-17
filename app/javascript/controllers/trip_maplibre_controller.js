import { Controller } from "@hotwired/stimulus"
import { MapInitializer } from "controllers/maps/maplibre/map_initializer"
import maplibregl from "maplibre-gl"
import { DayRoutesLayer } from "maps_maplibre/layers/day_routes_layer"
import { PhotosLayer } from "maps_maplibre/layers/photos_layer"
import { ReplayMarkerLayer } from "maps_maplibre/layers/replay_marker_layer"
import { ReplayManager } from "maps_maplibre/managers/replay_manager"
import { ApiClient } from "maps_maplibre/services/api_client"

/**
 * Trip MapLibre Controller
 * Renders a MapLibre map for the trip show page with day-colored routes,
 * an accordion-based day navigator, photos overlay, and trip replay.
 */
export default class extends Controller {
  static targets = [
    "map",
    "daysAccordion",
    "expandAllBtn",
    "loadingIndicator",
    // Photos button
    "photosToggleBtn",
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
    pathData: String,
    mapStyle: { type: String, default: "light" },
  }

  async connect() {
    this.pointsByDay = {}
    this.selectedDay = null
    this.dayRoutesLayer = null
    this.photosLayer = null
    this.photosGeoJSON = null
    this.photosActive = false
    this.mapInitializing = false
    this.overviewSourceId = "trip-overview-source"
    this.overviewLayerId = "trip-overview-layer"

    // Replay state
    this.replayManager = null
    this.replayMarkerLayer = null
    this.replayActive = false
    this.replaySpeed = 2
    this.replayPoints = []
    this.replayPointIndex = 0
    this.replayLastTime = 0
    this.replayAnimationId = null
    this.replayCurrentCoords = null
    this.replayNextCoords = null

    if (this.hasMapTarget) {
      await this.initializeMap()
    }
  }

  disconnect() {
    this._stopReplay()
    if (this.replayMarkerLayer) {
      this.replayMarkerLayer.clear()
    }
    if (this.photosLayer) {
      this.photosLayer.remove()
      this.photosLayer = null
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

  async mapTargetConnected() {
    if (!this.map && !this.mapInitializing) {
      await this.initializeMap()
    }
  }

  async initializeMap() {
    if (!this.hasMapTarget || this.mapInitializing) return
    this.mapInitializing = true

    this.map = await MapInitializer.initialize(this.mapTarget, {
      mapStyle: this.mapStyleValue,
      center: [0, 0],
      zoom: 2,
      showControls: true,
    })

    this.map.on("load", async () => {
      this.showPathOverview()
      await this.fetchAndProcessPoints()
    })
  }

  getPathData() {
    const raw =
      this.pathDataValue ||
      (this.hasMapTarget && this.mapTarget.dataset.pathCoordinates)
    return raw || null
  }

  showPathOverview() {
    const pathData = this.getPathData()
    if (!pathData) return

    try {
      const coordinates = JSON.parse(pathData)
      if (!coordinates.length) return

      if (this.map.getSource(this.overviewSourceId)) return

      const geojson = {
        type: "Feature",
        geometry: {
          type: "LineString",
          coordinates: coordinates,
        },
      }

      this.map.addSource(this.overviewSourceId, {
        type: "geojson",
        data: geojson,
      })

      this.map.addLayer({
        id: this.overviewLayerId,
        type: "line",
        source: this.overviewSourceId,
        layout: {
          "line-join": "round",
          "line-cap": "round",
        },
        paint: {
          "line-color": "#6366F1",
          "line-width": 3,
          "line-opacity": 0.8,
        },
      })

      const bounds = new maplibregl.LngLatBounds()
      for (const coord of coordinates) {
        bounds.extend(coord)
      }
      if (!bounds.isEmpty()) {
        this.map.fitBounds(bounds, { padding: 50, maxZoom: 15 })
      }
    } catch (e) {
      console.error("[TripMapLibre] Error showing path overview:", e)
    }
  }

  async fetchAndProcessPoints() {
    const apiClient = new ApiClient(this.apiKeyValue)

    try {
      this.showLoading(true)

      const { points: allPoints } = await apiClient.fetchAllPoints({
        start_at: this.startedAtValue,
        end_at: this.endedAtValue,
      })

      if (!allPoints?.length) {
        this.showLoading(false)
        return
      }

      // Use ReplayManager for canonical day grouping
      const grouper = new ReplayManager({ timezone: this.timezoneValue })
      grouper.setPoints(allPoints)
      this.pointsByDay = {}
      for (const dayKey of grouper.availableDays) {
        this.pointsByDay[dayKey] = grouper.getPointsForDay(dayKey)
      }
      const dayKeys = Object.keys(this.pointsByDay).sort()

      if (!dayKeys.length) {
        this.showLoading(false)
        return
      }

      this.removeOverviewLine()

      this.dayRoutesLayer = new DayRoutesLayer(this.map)
      this.dayRoutesLayer.addDayRoutes(this.pointsByDay)

      this.applyDayColors(dayKeys)

      this.dayRoutesLayer.setupInteractions({
        onDayClick: (dayKey) => this.selectDayFromMap(dayKey),
      })

      const fullBounds = this.dayRoutesLayer.getFullBounds()
      if (fullBounds) {
        this.map.fitBounds(fullBounds, { padding: 50, maxZoom: 15 })
      }

      // Store all points for replay use
      this.allPoints = allPoints

      // The replay panel may have been opened before points finished loading
      if (
        this.hasReplayPanelTarget &&
        !this.replayPanelTarget.classList.contains("hidden")
      ) {
        this._initializeReplayPanel()
      }

      this.showLoading(false)
    } catch (e) {
      console.error("[TripMapLibre] Error fetching points:", e)
      this.showLoading(false)
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

    this._syncReplayToDay(dayKey)
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

        const fullBounds = this.dayRoutesLayer.getFullBounds()
        if (fullBounds) {
          this.map.fitBounds(fullBounds, { padding: 50, maxZoom: 15 })
        }
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

      this._syncReplayToDay(dayKey)
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
        this.expandAllBtnTarget.textContent = "Show all days"
      }
    } else {
      for (const d of allDetails) {
        d.setAttribute("open", "")
      }
      if (this.hasExpandAllBtnTarget) {
        this.expandAllBtnTarget.textContent = "Collapse all days"
      }
    }

    this.selectedDay = null

    if (this.dayRoutesLayer) {
      this.dayRoutesLayer.selectAllDays()

      const fullBounds = this.dayRoutesLayer.getFullBounds()
      if (fullBounds) {
        this.map.fitBounds(fullBounds, { padding: 50, maxZoom: 15 })
      }
    }
  }

  removeOverviewLine() {
    if (this.map.getLayer(this.overviewLayerId)) {
      this.map.removeLayer(this.overviewLayerId)
    }
    if (this.map.getSource(this.overviewSourceId)) {
      this.map.removeSource(this.overviewSourceId)
    }
  }

  showLoading(show) {
    if (this.hasLoadingIndicatorTarget) {
      this.loadingIndicatorTarget.classList.toggle("hidden", !show)
    }
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
            taken_at: photo.localDateTime,
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

  // ===== Replay panel =====

  toggleReplay() {
    if (!this.hasReplayPanelTarget) return

    const isVisible = !this.replayPanelTarget.classList.contains("hidden")

    if (isVisible) {
      this._stopReplay()
      this.replayPanelTarget.classList.add("hidden")
      this._clearReplayMarker()
      this._updateReplaySpeedDisplay(null)
      this._setButtonActive(this.replayToggleBtnTarget, false)
    } else {
      this._initializeReplayPanel()
      this.replayPanelTarget.classList.remove("hidden")
      this._setButtonActive(this.replayToggleBtnTarget, true)
    }
  }

  _initializeReplayPanel() {
    if (!this.allPoints || this.allPoints.length === 0) return

    this.replayManager = new ReplayManager({
      timezone: this.timezoneValue,
    })

    this.replayManager.setPoints(this.allPoints)

    if (!this.replayManager.hasData()) return

    // Initialize replay marker layer if needed
    if (!this.replayMarkerLayer) {
      this.replayMarkerLayer = new ReplayMarkerLayer(this.map)
      this.replayMarkerLayer.add()
    }

    this._updateReplayDayDisplay()
    this._updateReplayDayCount()
    this._updateReplayDayButtons()
    this._renderReplayDensity()
    this._initializeReplayPlayback()
    this._setInitialScrubberPosition()
    this._hideReplayCycleControls()
  }

  _setInitialScrubberPosition() {
    if (!this.hasReplayScrubberTarget || !this.replayManager) return

    const firstMinute = this.replayManager.findNearestMinuteWithPoints(0)
    if (firstMinute !== null) {
      this.replayScrubberTarget.value = firstMinute
      this._handleReplayMinuteChange(firstMinute)
    } else {
      this.replayScrubberTarget.value = 720
      this._updateReplayTimeDisplay(720, true)
    }
  }

  replayScrubberHover(event) {
    const minute = parseInt(event.target.value, 10)
    this._handleReplayMinuteChange(minute)
  }

  _handleReplayMinuteChange(minute) {
    if (!this.replayManager) return

    const hasDataAtMinute = this.replayManager.hasDataAtMinute(minute)
    const nearestMinute = this.replayManager.findNearestMinuteWithPoints(minute)

    this._updateReplayTimeDisplay(minute, !hasDataAtMinute)

    if (nearestMinute === null) {
      this._clearReplayMarker()
      this._hideReplayCycleControls()
      this._updateReplaySpeedDisplay(null)
      return
    }

    if (!hasDataAtMinute || nearestMinute !== minute) {
      this.replayManager.resetCycle()
    }

    const point = this.replayManager.getPointAtPosition(nearestMinute)
    if (!point) return

    this._showReplayMarker(point)
    this._updateReplaySpeedDisplay(this._getPointVelocity(point))
    this._flyToReplayPoint(point, this.replayActive)

    if (hasDataAtMinute) {
      this._updateReplayCycleControls(minute)
    } else {
      this._hideReplayCycleControls()
    }

    // Sync replay day with accordion
    this._syncAccordionWithReplayDay()

    if (this.replayActive && this.replayPoints?.length > 0) {
      this._jumpReplayToMinute(minute)
    }
  }

  _jumpReplayToMinute(minute) {
    const dayPoints = this.replayPoints
    if (!dayPoints || dayPoints.length === 0) return

    let targetIndex = 0
    for (let i = 0; i < dayPoints.length; i++) {
      const timestamp = this.replayManager.getTimestamp(dayPoints[i])
      const pointTime = this._parseReplayTimestamp(timestamp)
      if (pointTime) {
        const date = new Date(pointTime)
        const pointMinute = date.getHours() * 60 + date.getMinutes()
        if (pointMinute >= minute) {
          targetIndex = i
          break
        }
        targetIndex = i
      }
    }

    this.replayPointIndex = targetIndex

    const currentPoint = dayPoints[targetIndex]
    const nextPoint = dayPoints[targetIndex + 1]

    this.replayCurrentCoords = currentPoint
      ? this.replayManager.getCoordinates(currentPoint)
      : null
    this.replayNextCoords = nextPoint
      ? this.replayManager.getCoordinates(nextPoint)
      : this.replayCurrentCoords

    this.replayLastTime = performance.now()
  }

  // --- Day navigation ---

  replayPrevDay() {
    if (!this.replayManager) return

    this._stopReplay()

    if (this.replayManager.prevDay()) {
      this._updateReplayDayDisplay()
      this._updateReplayDayCount()
      this._updateReplayDayButtons()
      this._renderReplayDensity()
      this._setInitialScrubberPosition()
      this._clearReplayMarker()
      this._hideReplayCycleControls()
      this._syncAccordionWithReplayDay()
    }
  }

  replayNextDay() {
    if (!this.replayManager) return

    this._stopReplay()

    if (this.replayManager.nextDay()) {
      this._updateReplayDayDisplay()
      this._updateReplayDayCount()
      this._updateReplayDayButtons()
      this._renderReplayDensity()
      this._setInitialScrubberPosition()
      this._clearReplayMarker()
      this._hideReplayCycleControls()
      this._syncAccordionWithReplayDay()
    }
  }

  // --- Point cycling ---

  replayCyclePrev() {
    if (!this.replayManager || !this.hasReplayScrubberTarget) return

    const minute = parseInt(this.replayScrubberTarget.value, 10)
    this.replayManager.cyclePrev()

    const point = this.replayManager.getPointAtPosition(minute)
    if (point) {
      this._showReplayMarker(point)
      this._updateReplaySpeedDisplay(this._getPointVelocity(point))
      this._flyToReplayPoint(point)
      this._updateReplayCycleControls(minute)
    }
  }

  replayCycleNext() {
    if (!this.replayManager || !this.hasReplayScrubberTarget) return

    const minute = parseInt(this.replayScrubberTarget.value, 10)
    this.replayManager.cycleNext(minute)

    const point = this.replayManager.getPointAtPosition(minute)
    if (point) {
      this._showReplayMarker(point)
      this._updateReplaySpeedDisplay(this._getPointVelocity(point))
      this._flyToReplayPoint(point)
      this._updateReplayCycleControls(minute)
    }
  }

  // --- UI updates ---

  _updateReplayDayDisplay() {
    if (!this.hasReplayDayDisplayTarget || !this.replayManager) return
    this.replayDayDisplayTarget.textContent =
      this.replayManager.getCurrentDayDisplay()
  }

  _updateReplayDayButtons() {
    if (!this.replayManager) return

    if (this.hasReplayPrevDayButtonTarget) {
      this.replayPrevDayButtonTarget.disabled = !this.replayManager.canGoPrev()
    }

    if (this.hasReplayNextDayButtonTarget) {
      this.replayNextDayButtonTarget.disabled = !this.replayManager.canGoNext()
    }
  }

  _updateReplayTimeDisplay(minute, showNoData = false) {
    if (this.hasReplayTimeDisplayTarget) {
      this.replayTimeDisplayTarget.textContent =
        ReplayManager.formatMinuteToTime(minute)
    }

    if (this.hasReplayDataIndicatorTarget) {
      if (showNoData) {
        this.replayDataIndicatorTarget.classList.remove("hidden")
        this.replayDataIndicatorTarget.textContent = "No data at this time"
      } else {
        this.replayDataIndicatorTarget.classList.add("hidden")
      }
    }
  }

  _getPointVelocity(point) {
    if (!point) return null
    if (point.properties?.velocity !== undefined) {
      return point.properties.velocity
    }
    if (point.velocity !== undefined) {
      return point.velocity
    }
    return null
  }

  _updateReplaySpeedDisplay(velocity) {
    if (!this.hasReplaySpeedDisplayTarget) return

    if (velocity !== null && velocity !== undefined && velocity !== "") {
      const speedMs = parseFloat(velocity)
      if (!Number.isNaN(speedMs) && speedMs > 0) {
        const speedKmh = speedMs * 3.6
        this.replaySpeedDisplayTarget.textContent = `${Math.round(speedKmh)} km/h`
      } else {
        this.replaySpeedDisplayTarget.textContent = ""
      }
    } else {
      this.replaySpeedDisplayTarget.textContent = ""
    }
  }

  _updateReplayDayCount() {
    if (!this.hasReplayDayCountTarget || !this.replayManager) return

    const dayCount = this.replayManager.getDayCount()
    const currentIndex = this.replayManager.currentDayIndex + 1
    const pointCount = this.replayManager.getCurrentDayPointCount()

    this.replayDayCountTarget.textContent = `Day ${currentIndex} of ${dayCount} \u2022 ${pointCount.toLocaleString()} points`
  }

  _renderReplayDensity() {
    if (!this.hasReplayDensityContainerTarget || !this.replayManager) return

    const segments = 48
    const density = this.replayManager.getDataDensity(segments)

    while (this.replayDensityContainerTarget.firstChild) {
      this.replayDensityContainerTarget.removeChild(
        this.replayDensityContainerTarget.firstChild,
      )
    }

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

  _hideReplayCycleControls() {
    if (this.hasReplayCycleControlsTarget) {
      this.replayCycleControlsTarget.classList.add("hidden")
    }
  }

  // ===== Replay playback =====

  replayTogglePlayback() {
    if (this.replayActive) {
      this._stopReplay()
    } else {
      this._startReplay()
    }
  }

  replaySpeedChange(event) {
    const speedIndex = parseInt(event.target.value, 10)
    const speeds = [1, 2, 5, 10]
    this.replaySpeed = speeds[speedIndex - 1] || 2

    if (this.hasReplaySpeedLabelTarget) {
      this.replaySpeedLabelTarget.textContent = `${this.replaySpeed}x`
    }
  }

  _startReplay() {
    if (this.replayActive) return
    if (!this.replayManager || !this.hasReplayScrubberTarget) return

    const currentDay = this.replayManager.getCurrentDay()
    if (!currentDay) return

    const dayPoints = this.replayManager.getPointsForDay(currentDay)
    if (dayPoints.length === 0) return

    this.replayActive = true
    this.replaySpeed = this.replaySpeed || 2
    this.replayPoints = dayPoints
    this.replayPointIndex = 0

    const currentMinute = parseInt(this.replayScrubberTarget.value, 10)
    for (let i = 0; i < dayPoints.length; i++) {
      const timestamp = this.replayManager.getTimestamp(dayPoints[i])
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

    const startPoint = dayPoints[this.replayPointIndex]
    const nextPoint = dayPoints[this.replayPointIndex + 1]
    this.replayCurrentCoords = startPoint
      ? this.replayManager.getCoordinates(startPoint)
      : null
    this.replayNextCoords = nextPoint
      ? this.replayManager.getCoordinates(nextPoint)
      : this.replayCurrentCoords

    if (startPoint) {
      this._showReplayMarker(startPoint)
      this._flyToReplayPoint(startPoint, true)
    }

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
    this._replayFrame()
  }

  _stopReplay() {
    if (this.replayActive === undefined) return

    this.replayActive = false

    if (this.replayAnimationId) {
      cancelAnimationFrame(this.replayAnimationId)
      this.replayAnimationId = null
    }

    if (this.hasReplayPlayButtonTarget) {
      this.replayPlayButtonTarget.classList.remove("playing")
    }
    if (this.hasReplayPlayIconTarget) {
      this.replayPlayIconTarget.classList.remove("hidden")
    }
    if (this.hasReplayPauseIconTarget) {
      this.replayPauseIconTarget.classList.add("hidden")
    }
  }

  _initializeReplayPlayback() {
    this.replayActive = false
    this.replaySpeed = 2
    this.replayPoints = []
    this.replayPointIndex = 0
    this.replayLastTime = 0
    this.replayAnimationId = null
    this.replayCurrentCoords = null
    this.replayNextCoords = null

    if (this.hasReplaySpeedLabelTarget) {
      this.replaySpeedLabelTarget.textContent = "2x"
    }
    if (this.hasReplaySpeedSliderTarget) {
      this.replaySpeedSliderTarget.value = 2
    }
  }

  _replayFrame() {
    if (!this.replayActive) return

    const now = performance.now()
    const elapsed = now - this.replayLastTime
    const intervalMs = 500 / this.replaySpeed
    const progress = Math.min(elapsed / intervalMs, 1)

    if (this.replayCurrentCoords && this.replayNextCoords) {
      const currentLon =
        this.replayCurrentCoords.lon +
        (this.replayNextCoords.lon - this.replayCurrentCoords.lon) * progress
      const currentLat =
        this.replayCurrentCoords.lat +
        (this.replayNextCoords.lat - this.replayCurrentCoords.lat) * progress

      this._showReplayMarkerAt(currentLon, currentLat)
      this._panMapToFollowMarker(currentLon, currentLat)
    }

    if (elapsed >= intervalMs) {
      this.replayLastTime = now
      this.replayPointIndex++

      if (this.replayPointIndex >= this.replayPoints.length) {
        if (this.replayManager.canGoNext()) {
          this.replayManager.nextDay()
          this._updateReplayDayDisplay()
          this._updateReplayDayCount()
          this._updateReplayDayButtons()
          this._renderReplayDensity()
          this._syncAccordionWithReplayDay()

          const newDay = this.replayManager.getCurrentDay()
          this.replayPoints = this.replayManager.getPointsForDay(newDay)
          this.replayPointIndex = 0

          if (this.replayPoints.length === 0) {
            this._stopReplay()
            return
          }
        } else {
          this._stopReplay()
          return
        }
      }

      const currentPoint = this.replayPoints[this.replayPointIndex]
      const nextPoint = this.replayPoints[this.replayPointIndex + 1]

      if (!currentPoint) {
        this._stopReplay()
        return
      }

      this.replayCurrentCoords = this.replayManager.getCoordinates(currentPoint)
      this.replayNextCoords = nextPoint
        ? this.replayManager.getCoordinates(nextPoint)
        : this.replayCurrentCoords

      this._updateReplaySpeedDisplay(this._getPointVelocity(currentPoint))

      const timestamp = this.replayManager.getTimestamp(currentPoint)
      const pointTime = this._parseReplayTimestamp(timestamp)
      if (pointTime) {
        const date = new Date(pointTime)
        const minute = date.getHours() * 60 + date.getMinutes()

        this.replayScrubberTarget.value = minute
        this._updateReplayTimeDisplay(minute, false)
      }

      this._hideReplayCycleControls()
    }

    this.replayAnimationId = requestAnimationFrame(() => this._replayFrame())
  }

  _panMapToFollowMarker(lon, lat) {
    if (!this.map) return

    const bounds = this.map.getBounds()
    const center = this.map.getCenter()

    const lngSpan = bounds.getEast() - bounds.getWest()
    const latSpan = bounds.getNorth() - bounds.getSouth()

    const lngOffset = (lon - center.lng) / lngSpan
    const latOffset = (lat - center.lat) / latSpan

    const threshold = 0.3
    if (Math.abs(lngOffset) > threshold || Math.abs(latOffset) > threshold) {
      this.map.setCenter([lon, lat])
    }
  }

  // --- Marker helpers ---

  _showReplayMarker(point) {
    const coords = this.replayManager?.getCoordinates(point)
    if (!coords) return

    if (this.replayMarkerLayer) {
      this.replayMarkerLayer.showMarker(coords.lon, coords.lat, {
        timestamp: this.replayManager.getTimestamp(point),
      })
    }
  }

  _showReplayMarkerAt(lon, lat) {
    if (lon === undefined || lat === undefined) return

    if (this.replayMarkerLayer) {
      this.replayMarkerLayer.showMarker(lon, lat)
    }
  }

  _clearReplayMarker() {
    if (this.replayMarkerLayer) {
      this.replayMarkerLayer.clear()
    }
  }

  _flyToReplayPoint(point, fast = false) {
    const coords = this.replayManager?.getCoordinates(point)
    if (!coords || !this.map) return

    this.map.flyTo({
      center: [coords.lon, coords.lat],
      zoom: Math.max(this.map.getZoom(), 14),
      duration: fast ? 100 : 500,
    })
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

  // --- Replay <-> day sync ---

  _syncReplayToDay(dayKey) {
    if (!this.replayManager) return
    if (!this.hasReplayPanelTarget) return
    if (this.replayPanelTarget.classList.contains("hidden")) return

    this._stopReplay()

    if (this.replayManager.goToDay(dayKey)) {
      this._updateReplayDayDisplay()
      this._updateReplayDayCount()
      this._updateReplayDayButtons()
      this._renderReplayDensity()
      this._setInitialScrubberPosition()
      this._clearReplayMarker()
      this._hideReplayCycleControls()
    }
  }

  // --- Accordion sync ---

  _syncAccordionWithReplayDay() {
    if (!this.hasDaysAccordionTarget || !this.replayManager) return

    const currentDay = this.replayManager.getCurrentDay()
    if (!currentDay) return

    const allDetails = this.daysAccordionTarget.querySelectorAll(
      "details[data-day-key]",
    )
    const target = this.daysAccordionTarget.querySelector(
      `details[data-day-key="${currentDay}"]`,
    )

    for (const d of allDetails) {
      if (d !== target) {
        d.removeAttribute("open")
      }
    }

    if (target) {
      target.setAttribute("open", "")
      target.scrollIntoView({ behavior: "smooth", block: "nearest" })
    }

    // Also highlight the day route on the map
    if (this.dayRoutesLayer) {
      this.dayRoutesLayer.selectDay(currentDay)
    }
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
