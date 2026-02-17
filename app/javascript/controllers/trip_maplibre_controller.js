import { Controller } from "@hotwired/stimulus"
import { MapInitializer } from "controllers/maps/maplibre/map_initializer"
import maplibregl from "maplibre-gl"
import { DayRoutesLayer } from "maps_maplibre/layers/day_routes_layer"
import { PhotosLayer } from "maps_maplibre/layers/photos_layer"
import { TimelineMarkerLayer } from "maps_maplibre/layers/timeline_marker_layer"
import { TimelineManager } from "maps_maplibre/managers/timeline_manager"
import { ApiClient } from "maps_maplibre/services/api_client"

/**
 * Trip MapLibre Controller
 * Renders a MapLibre map for the trip show page with day-colored routes,
 * an accordion-based day navigator, photos overlay, and timeline replay.
 */
export default class extends Controller {
  static targets = [
    "map",
    "daysAccordion",
    "expandAllBtn",
    "loadingIndicator",
    // Photos button
    "photosToggleBtn",
    // Timeline toggle button
    "timelineToggleBtn",
    // Timeline panel
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
    "timelinePlayButton",
    "timelinePlayIcon",
    "timelinePauseIcon",
    "timelineSpeedSlider",
    "timelineSpeedLabel",
    "timelineSpeedDisplay",
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

    // Timeline state
    this.timelineManager = null
    this.timelineMarkerLayer = null
    this.timelineReplayActive = false
    this.timelineReplaySpeed = 2
    this.timelineReplayPoints = []
    this.timelineReplayPointIndex = 0
    this.timelineReplayLastTime = 0
    this.timelineReplayAnimationId = null
    this.timelineReplayCurrentCoords = null
    this.timelineReplayNextCoords = null

    if (this.hasMapTarget) {
      await this.initializeMap()
    }
  }

  disconnect() {
    this._stopTimelineReplay()
    if (this.timelineMarkerLayer) {
      this.timelineMarkerLayer.clear()
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

      const allPoints = await apiClient.fetchAllPoints({
        start_at: this.startedAtValue,
        end_at: this.endedAtValue,
      })

      if (!allPoints.length) {
        this.showLoading(false)
        return
      }

      // Use TimelineManager for canonical day grouping
      const grouper = new TimelineManager({ timezone: this.timezoneValue })
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

      // Store all points for timeline use
      this.allPoints = allPoints

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

    this._syncTimelineToDay(dayKey)
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

      this._syncTimelineToDay(dayKey)
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

  // ===== Timeline =====

  toggleTimeline() {
    if (!this.hasTimelinePanelTarget) return

    const isVisible = !this.timelinePanelTarget.classList.contains("hidden")

    if (isVisible) {
      this._stopTimelineReplay()
      this.timelinePanelTarget.classList.add("hidden")
      this._clearTimelineMarker()
      this._updateTimelineSpeedDisplay(null)
      this._setButtonActive(this.timelineToggleBtnTarget, false)
    } else {
      this._initializeTimeline()
      this.timelinePanelTarget.classList.remove("hidden")
      this._setButtonActive(this.timelineToggleBtnTarget, true)
    }
  }

  _initializeTimeline() {
    if (!this.allPoints || this.allPoints.length === 0) return

    this.timelineManager = new TimelineManager({
      timezone: this.timezoneValue,
    })

    this.timelineManager.setPoints(this.allPoints)

    if (!this.timelineManager.hasData()) return

    // Initialize timeline marker layer if needed
    if (!this.timelineMarkerLayer) {
      this.timelineMarkerLayer = new TimelineMarkerLayer(this.map)
      this.timelineMarkerLayer.add()
    }

    this._updateTimelineDayDisplay()
    this._updateTimelineDayCount()
    this._updateTimelineDayButtons()
    this._renderTimelineDensity()
    this._initializeTimelineReplay()
    this._setInitialScrubberPosition()
    this._hideTimelineCycleControls()
  }

  _setInitialScrubberPosition() {
    if (!this.hasTimelineScrubberTarget || !this.timelineManager) return

    const firstMinute = this.timelineManager.findNearestMinuteWithPoints(0)
    if (firstMinute !== null) {
      this.timelineScrubberTarget.value = firstMinute
      this._handleTimelineMinuteChange(firstMinute)
    } else {
      this.timelineScrubberTarget.value = 720
      this._updateTimelineTimeDisplay(720, true)
    }
  }

  timelineScrubberHover(event) {
    const minute = parseInt(event.target.value, 10)
    this._handleTimelineMinuteChange(minute)
  }

  _handleTimelineMinuteChange(minute) {
    if (!this.timelineManager) return

    const hasDataAtMinute = this.timelineManager.hasDataAtMinute(minute)
    const nearestMinute =
      this.timelineManager.findNearestMinuteWithPoints(minute)

    this._updateTimelineTimeDisplay(minute, !hasDataAtMinute)

    if (nearestMinute === null) {
      this._clearTimelineMarker()
      this._hideTimelineCycleControls()
      this._updateTimelineSpeedDisplay(null)
      return
    }

    if (!hasDataAtMinute || nearestMinute !== minute) {
      this.timelineManager.resetCycle()
    }

    const point = this.timelineManager.getPointAtPosition(nearestMinute)
    if (!point) return

    this._showTimelineMarker(point)
    this._updateTimelineSpeedDisplay(this._getPointVelocity(point))
    this._flyToTimelinePoint(point, this.timelineReplayActive)

    if (hasDataAtMinute) {
      this._updateTimelineCycleControls(minute)
    } else {
      this._hideTimelineCycleControls()
    }

    // Sync timeline day with accordion
    this._syncAccordionWithTimelineDay()

    if (this.timelineReplayActive && this.timelineReplayPoints?.length > 0) {
      this._jumpReplayToMinute(minute)
    }
  }

  _jumpReplayToMinute(minute) {
    const dayPoints = this.timelineReplayPoints
    if (!dayPoints || dayPoints.length === 0) return

    let targetIndex = 0
    for (let i = 0; i < dayPoints.length; i++) {
      const timestamp = this.timelineManager.getTimestamp(dayPoints[i])
      const pointTime = this._parseTimelineTimestamp(timestamp)
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

    this.timelineReplayPointIndex = targetIndex

    const currentPoint = dayPoints[targetIndex]
    const nextPoint = dayPoints[targetIndex + 1]

    this.timelineReplayCurrentCoords = currentPoint
      ? this.timelineManager.getCoordinates(currentPoint)
      : null
    this.timelineReplayNextCoords = nextPoint
      ? this.timelineManager.getCoordinates(nextPoint)
      : this.timelineReplayCurrentCoords

    this.timelineReplayLastTime = performance.now()
  }

  // --- Day navigation ---

  timelinePrevDay() {
    if (!this.timelineManager) return

    this._stopTimelineReplay()

    if (this.timelineManager.prevDay()) {
      this._updateTimelineDayDisplay()
      this._updateTimelineDayCount()
      this._updateTimelineDayButtons()
      this._renderTimelineDensity()
      this._setInitialScrubberPosition()
      this._clearTimelineMarker()
      this._hideTimelineCycleControls()
      this._syncAccordionWithTimelineDay()
    }
  }

  timelineNextDay() {
    if (!this.timelineManager) return

    this._stopTimelineReplay()

    if (this.timelineManager.nextDay()) {
      this._updateTimelineDayDisplay()
      this._updateTimelineDayCount()
      this._updateTimelineDayButtons()
      this._renderTimelineDensity()
      this._setInitialScrubberPosition()
      this._clearTimelineMarker()
      this._hideTimelineCycleControls()
      this._syncAccordionWithTimelineDay()
    }
  }

  // --- Point cycling ---

  timelineCyclePrev() {
    if (!this.timelineManager || !this.hasTimelineScrubberTarget) return

    const minute = parseInt(this.timelineScrubberTarget.value, 10)
    this.timelineManager.cyclePrev()

    const point = this.timelineManager.getPointAtPosition(minute)
    if (point) {
      this._showTimelineMarker(point)
      this._updateTimelineSpeedDisplay(this._getPointVelocity(point))
      this._flyToTimelinePoint(point)
      this._updateTimelineCycleControls(minute)
    }
  }

  timelineCycleNext() {
    if (!this.timelineManager || !this.hasTimelineScrubberTarget) return

    const minute = parseInt(this.timelineScrubberTarget.value, 10)
    this.timelineManager.cycleNext(minute)

    const point = this.timelineManager.getPointAtPosition(minute)
    if (point) {
      this._showTimelineMarker(point)
      this._updateTimelineSpeedDisplay(this._getPointVelocity(point))
      this._flyToTimelinePoint(point)
      this._updateTimelineCycleControls(minute)
    }
  }

  // --- UI updates ---

  _updateTimelineDayDisplay() {
    if (!this.hasTimelineDayDisplayTarget || !this.timelineManager) return
    this.timelineDayDisplayTarget.textContent =
      this.timelineManager.getCurrentDayDisplay()
  }

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

  _updateTimelineTimeDisplay(minute, showNoData = false) {
    if (this.hasTimelineTimeDisplayTarget) {
      this.timelineTimeDisplayTarget.textContent =
        TimelineManager.formatMinuteToTime(minute)
    }

    if (this.hasTimelineDataIndicatorTarget) {
      if (showNoData) {
        this.timelineDataIndicatorTarget.classList.remove("hidden")
        this.timelineDataIndicatorTarget.textContent = "No data at this time"
      } else {
        this.timelineDataIndicatorTarget.classList.add("hidden")
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

  _updateTimelineSpeedDisplay(velocity) {
    if (!this.hasTimelineSpeedDisplayTarget) return

    if (velocity !== null && velocity !== undefined && velocity !== "") {
      const speedMs = parseFloat(velocity)
      if (!Number.isNaN(speedMs) && speedMs > 0) {
        const speedKmh = speedMs * 3.6
        this.timelineSpeedDisplayTarget.textContent = `${Math.round(speedKmh)} km/h`
      } else {
        this.timelineSpeedDisplayTarget.textContent = ""
      }
    } else {
      this.timelineSpeedDisplayTarget.textContent = ""
    }
  }

  _updateTimelineDayCount() {
    if (!this.hasTimelineDayCountTarget || !this.timelineManager) return

    const dayCount = this.timelineManager.getDayCount()
    const currentIndex = this.timelineManager.currentDayIndex + 1
    const pointCount = this.timelineManager.getCurrentDayPointCount()

    this.timelineDayCountTarget.textContent = `Day ${currentIndex} of ${dayCount} \u2022 ${pointCount.toLocaleString()} points`
  }

  _renderTimelineDensity() {
    if (!this.hasTimelineDensityContainerTarget || !this.timelineManager) return

    const segments = 48
    const density = this.timelineManager.getDataDensity(segments)

    while (this.timelineDensityContainerTarget.firstChild) {
      this.timelineDensityContainerTarget.removeChild(
        this.timelineDensityContainerTarget.firstChild,
      )
    }

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

  _hideTimelineCycleControls() {
    if (this.hasTimelineCycleControlsTarget) {
      this.timelineCycleControlsTarget.classList.add("hidden")
    }
  }

  // ===== Timeline Replay =====

  timelineToggleReplay() {
    if (this.timelineReplayActive) {
      this._stopTimelineReplay()
    } else {
      this._startTimelineReplay()
    }
  }

  timelineSpeedChange(event) {
    const speedIndex = parseInt(event.target.value, 10)
    const speeds = [1, 2, 5, 10]
    this.timelineReplaySpeed = speeds[speedIndex - 1] || 2

    if (this.hasTimelineSpeedLabelTarget) {
      this.timelineSpeedLabelTarget.textContent = `${this.timelineReplaySpeed}x`
    }
  }

  _startTimelineReplay() {
    if (this.timelineReplayActive) return
    if (!this.timelineManager || !this.hasTimelineScrubberTarget) return

    const currentDay = this.timelineManager.getCurrentDay()
    if (!currentDay) return

    const dayPoints = this.timelineManager.getPointsForDay(currentDay)
    if (dayPoints.length === 0) return

    this.timelineReplayActive = true
    this.timelineReplaySpeed = this.timelineReplaySpeed || 2
    this.timelineReplayPoints = dayPoints
    this.timelineReplayPointIndex = 0

    const currentMinute = parseInt(this.timelineScrubberTarget.value, 10)
    for (let i = 0; i < dayPoints.length; i++) {
      const timestamp = this.timelineManager.getTimestamp(dayPoints[i])
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

    const startPoint = dayPoints[this.timelineReplayPointIndex]
    const nextPoint = dayPoints[this.timelineReplayPointIndex + 1]
    this.timelineReplayCurrentCoords = startPoint
      ? this.timelineManager.getCoordinates(startPoint)
      : null
    this.timelineReplayNextCoords = nextPoint
      ? this.timelineManager.getCoordinates(nextPoint)
      : this.timelineReplayCurrentCoords

    if (startPoint) {
      this._showTimelineMarker(startPoint)
      this._flyToTimelinePoint(startPoint, true)
    }

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
    this._timelineReplayFrame()
  }

  _stopTimelineReplay() {
    if (this.timelineReplayActive === undefined) return

    this.timelineReplayActive = false

    if (this.timelineReplayAnimationId) {
      cancelAnimationFrame(this.timelineReplayAnimationId)
      this.timelineReplayAnimationId = null
    }

    if (this.hasTimelinePlayButtonTarget) {
      this.timelinePlayButtonTarget.classList.remove("playing")
    }
    if (this.hasTimelinePlayIconTarget) {
      this.timelinePlayIconTarget.classList.remove("hidden")
    }
    if (this.hasTimelinePauseIconTarget) {
      this.timelinePauseIconTarget.classList.add("hidden")
    }
  }

  _initializeTimelineReplay() {
    this.timelineReplayActive = false
    this.timelineReplaySpeed = 2
    this.timelineReplayPoints = []
    this.timelineReplayPointIndex = 0
    this.timelineReplayLastTime = 0
    this.timelineReplayAnimationId = null
    this.timelineReplayCurrentCoords = null
    this.timelineReplayNextCoords = null

    if (this.hasTimelineSpeedLabelTarget) {
      this.timelineSpeedLabelTarget.textContent = "2x"
    }
    if (this.hasTimelineSpeedSliderTarget) {
      this.timelineSpeedSliderTarget.value = 2
    }
  }

  _timelineReplayFrame() {
    if (!this.timelineReplayActive) return

    const now = performance.now()
    const elapsed = now - this.timelineReplayLastTime
    const intervalMs = 500 / this.timelineReplaySpeed
    const progress = Math.min(elapsed / intervalMs, 1)

    if (this.timelineReplayCurrentCoords && this.timelineReplayNextCoords) {
      const currentLon =
        this.timelineReplayCurrentCoords.lon +
        (this.timelineReplayNextCoords.lon -
          this.timelineReplayCurrentCoords.lon) *
          progress
      const currentLat =
        this.timelineReplayCurrentCoords.lat +
        (this.timelineReplayNextCoords.lat -
          this.timelineReplayCurrentCoords.lat) *
          progress

      this._showTimelineMarkerAt(currentLon, currentLat)
      this._panMapToFollowMarker(currentLon, currentLat)
    }

    if (elapsed >= intervalMs) {
      this.timelineReplayLastTime = now
      this.timelineReplayPointIndex++

      if (this.timelineReplayPointIndex >= this.timelineReplayPoints.length) {
        if (this.timelineManager.canGoNext()) {
          this.timelineManager.nextDay()
          this._updateTimelineDayDisplay()
          this._updateTimelineDayCount()
          this._updateTimelineDayButtons()
          this._renderTimelineDensity()
          this._syncAccordionWithTimelineDay()

          const newDay = this.timelineManager.getCurrentDay()
          this.timelineReplayPoints =
            this.timelineManager.getPointsForDay(newDay)
          this.timelineReplayPointIndex = 0

          if (this.timelineReplayPoints.length === 0) {
            this._stopTimelineReplay()
            return
          }
        } else {
          this._stopTimelineReplay()
          return
        }
      }

      const currentPoint =
        this.timelineReplayPoints[this.timelineReplayPointIndex]
      const nextPoint =
        this.timelineReplayPoints[this.timelineReplayPointIndex + 1]

      if (!currentPoint) {
        this._stopTimelineReplay()
        return
      }

      this.timelineReplayCurrentCoords =
        this.timelineManager.getCoordinates(currentPoint)
      this.timelineReplayNextCoords = nextPoint
        ? this.timelineManager.getCoordinates(nextPoint)
        : this.timelineReplayCurrentCoords

      this._updateTimelineSpeedDisplay(this._getPointVelocity(currentPoint))

      const timestamp = this.timelineManager.getTimestamp(currentPoint)
      const pointTime = this._parseTimelineTimestamp(timestamp)
      if (pointTime) {
        const date = new Date(pointTime)
        const minute = date.getHours() * 60 + date.getMinutes()

        this.timelineScrubberTarget.value = minute
        this._updateTimelineTimeDisplay(minute, false)
      }

      this._hideTimelineCycleControls()
    }

    this.timelineReplayAnimationId = requestAnimationFrame(() =>
      this._timelineReplayFrame(),
    )
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

  _showTimelineMarker(point) {
    const coords = this.timelineManager?.getCoordinates(point)
    if (!coords) return

    if (this.timelineMarkerLayer) {
      this.timelineMarkerLayer.showMarker(coords.lon, coords.lat, {
        timestamp: this.timelineManager.getTimestamp(point),
      })
    }
  }

  _showTimelineMarkerAt(lon, lat) {
    if (lon === undefined || lat === undefined) return

    if (this.timelineMarkerLayer) {
      this.timelineMarkerLayer.showMarker(lon, lat)
    }
  }

  _clearTimelineMarker() {
    if (this.timelineMarkerLayer) {
      this.timelineMarkerLayer.clear()
    }
  }

  _flyToTimelinePoint(point, fast = false) {
    const coords = this.timelineManager?.getCoordinates(point)
    if (!coords || !this.map) return

    this.map.flyTo({
      center: [coords.lon, coords.lat],
      zoom: Math.max(this.map.getZoom(), 14),
      duration: fast ? 100 : 500,
    })
  }

  _parseTimelineTimestamp(timestamp) {
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

  // --- Timeline <-> day sync ---

  _syncTimelineToDay(dayKey) {
    if (!this.timelineManager) return
    if (!this.hasTimelinePanelTarget) return
    if (this.timelinePanelTarget.classList.contains("hidden")) return

    this._stopTimelineReplay()

    if (this.timelineManager.goToDay(dayKey)) {
      this._updateTimelineDayDisplay()
      this._updateTimelineDayCount()
      this._updateTimelineDayButtons()
      this._renderTimelineDensity()
      this._setInitialScrubberPosition()
      this._clearTimelineMarker()
      this._hideTimelineCycleControls()
    }
  }

  // --- Accordion sync ---

  _syncAccordionWithTimelineDay() {
    if (!this.hasDaysAccordionTarget || !this.timelineManager) return

    const currentDay = this.timelineManager.getCurrentDay()
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
