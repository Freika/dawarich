import { ReplayPhotoStack } from "maps_maplibre/components/replay_photo_stack"
import { ReplayMarkerLayer } from "maps_maplibre/layers/replay_marker_layer"
import { ReplayPhotoLayer } from "maps_maplibre/layers/replay_photo_layer"
import { ReplayManager } from "maps_maplibre/managers/replay_manager"
import { ReplayPhotoIndex } from "maps_maplibre/managers/replay_photo_index"

export class ReplayPanel {
  constructor(opts) {
    this.c = opts.controller
    this.map = opts.map
    this.timezone = opts.timezone
    this.allPoints = opts.allPoints || []
    this.dayRoutesLayer = opts.dayRoutesLayer || null
    this.element = opts.element || null
    this._markerLayerOpt = opts.markerLayer || null
    this._loadPoints = opts.loadPoints || null
    this._highlightPoint = opts.highlightPoint || null
    this._clearHighlight = opts.clearHighlight || null
    this.onDaySync = opts.onDaySync || null
    this.onPlayStateChange = opts.onPlayStateChange || null
    this._getPhotos = opts.getPhotos || null
    this._onReplayPhotosActive = opts.onReplayPhotosActive || (() => {})
    this._replayPhotoLayer = null
    this._photoIndex = null
    this._replayPhotoStack = null
    this._lastPlayheadMs = null
  }

  get isOpen() {
    return (
      this.c.hasReplayPanelTarget &&
      !this.c.replayPanelTarget.classList.contains("hidden")
    )
  }

  get isPlaying() {
    return !!this.replayActive
  }

  get manager() {
    return this.replayManager
  }

  get markerLayer() {
    if (typeof this._markerLayerOpt === "function")
      return this._markerLayerOpt()
    return this._markerLayerOpt || this._ownMarkerLayer || null
  }

  async toggle() {
    if (!this.c.hasReplayPanelTarget) return

    if (this.isOpen) {
      this.stopPlayback()
      this.c.replayPanelTarget.classList.add("hidden")
      this.clearMarker()
      this.clearHighlight()
      this.teardownReplayPhotos()
      this.updateSpeedDisplay(null)
      this.setButtonActive(false)
    } else {
      await this.init()
      this.c.replayPanelTarget.classList.remove("hidden")
      this.setButtonActive(true)
    }
  }

  async init() {
    const points = this._loadPoints ? await this._loadPoints() : this.allPoints
    if (!points?.length) return

    this.replayManager = new ReplayManager({ timezone: this.timezone })
    this.replayManager.setPoints(points)
    if (!this.replayManager.hasData()) return

    if (!this._markerLayerOpt && !this._ownMarkerLayer) {
      this._ownMarkerLayer = new ReplayMarkerLayer(this.map)
      this._ownMarkerLayer.add()
    }

    this.bindFollowInterrupt()
    this.setupReplayPhotos()
    this.updateDayDisplay()
    this.updateDayCount()
    this.updateDayButtons()
    this.renderDensity()
    this.initPlayback()
    this.setInitialScrubberPosition()
    this.hideCycleControls()
  }

  setupReplayPhotos() {
    if (!this._getPhotos) return

    const photos = this._getPhotos()
    if (!photos?.length) return

    this._photoIndex = new ReplayPhotoIndex({
      photos,
      timezone: this.timezone,
      getCoordinates: (photo) => this.replayManager.getCoordinates(photo),
    })
    if (!this._photoIndex.hasPhotos()) {
      this._photoIndex = null
      return
    }

    this._replayPhotoLayer = new ReplayPhotoLayer(this.map, {
      timezone: this.timezone,
    })
    this._replayPhotoLayer.setPhotos(this._photoIndex.allPhotos())
    this._replayPhotoStack = new ReplayPhotoStack(this.map, {
      timezone: this.timezone,
    })
    this._onReplayPhotosActive(true)
  }

  updateRevealedPhotos(playheadMs) {
    if (playheadMs === null || playheadMs === undefined) return
    this._lastPlayheadMs = playheadMs
    if (!this._replayPhotoLayer || !this._photoIndex) return

    const day = this.replayManager?.getCurrentDay()
    if (!day) return

    const revealed = this._photoIndex.revealedPhotos(day, playheadMs)
    const revealIds = new Set(revealed.map((photo) => photo.id))
    for (const photo of this._photoIndex.dayPhotos(day)) {
      if (revealIds.has(photo.id)) {
        this._replayPhotoLayer.reveal(photo.id)
      } else {
        this._replayPhotoLayer.hide(photo.id)
      }
    }
    this._replayPhotoStack?.sync(revealed)
  }

  resetReplayPhotos() {
    if (this._replayPhotoLayer) this._replayPhotoLayer.hideAll()
    if (this._replayPhotoStack) this._replayPhotoStack.clear()
  }

  refreshReplayPhotos() {
    if (!this.replayManager) return
    this.teardownReplayPhotos()
    this.setupReplayPhotos()
    if (this._lastPlayheadMs !== null && this._lastPlayheadMs !== undefined) {
      this.updateRevealedPhotos(this._lastPlayheadMs)
    }
  }

  teardownReplayPhotos() {
    if (this._replayPhotoLayer) {
      this._replayPhotoLayer.clear()
      this._replayPhotoLayer = null
    }
    if (this._replayPhotoStack) {
      this._replayPhotoStack.destroy()
      this._replayPhotoStack = null
    }
    if (this._photoIndex) {
      this._photoIndex = null
      this._onReplayPhotosActive(false)
    }
  }

  async ensureOpen() {
    if (!this.replayManager) await this.init()
    if (!this.isOpen) {
      this.c.replayPanelTarget.classList.remove("hidden")
      this.setButtonActive(true)
    }
  }

  destroy() {
    this.stopPlayback()
    this.clearMarker()
    this.clearHighlight()
    this.teardownReplayPhotos()
    this.unbindFollowInterrupt()
    this.replayManager = null
  }

  setInitialScrubberPosition() {
    if (!this.c.hasReplayScrubberTarget || !this.replayManager) return

    const firstMinute = this.replayManager.findNearestMinuteWithPoints(0)
    if (firstMinute !== null) {
      this.c.replayScrubberTarget.value = firstMinute
      this.handleMinuteChange(firstMinute)
    } else {
      this.c.replayScrubberTarget.value = 720
      this.updateTimeDisplay(720, true)
    }
  }

  setMinute(minute) {
    if (this.c.hasReplayScrubberTarget)
      this.c.replayScrubberTarget.value = minute
    this.handleMinuteChange(minute)
  }

  scrubberHover(event) {
    this.handleMinuteChange(parseInt(event.target.value, 10))
  }

  handleMinuteChange(minute) {
    if (!this.replayManager) return

    const hasDataAtMinute = this.replayManager.hasDataAtMinute(minute)
    const nearestMinute = this.replayManager.findNearestMinuteWithPoints(minute)

    this.updateTimeDisplay(minute, !hasDataAtMinute)

    if (nearestMinute === null) {
      this.clearMarker()
      this.clearHighlight()
      this.resetReplayPhotos()
      this.hideCycleControls()
      this.updateSpeedDisplay(null)
      return
    }

    if (!hasDataAtMinute || nearestMinute !== minute) {
      this.replayManager.resetCycle()
    }

    const point = this.replayManager.getPointAtPosition(nearestMinute)
    if (!point) return

    this.showMarker(point)
    this.updateRevealedPhotos(
      this.parseTimestamp(this.replayManager.getTimestamp(point)),
    )
    this.updateSpeedDisplay(this.getPointVelocity(point))
    this.flyToPoint(point, this.replayActive)
    this.highlightPoint(point)

    if (hasDataAtMinute) {
      this.updateCycleControls(minute)
    } else {
      this.hideCycleControls()
    }

    this.syncAccordion()

    if (this.replayActive && this.replayPoints?.length > 0) {
      this.jumpToMinute(minute)
    }
  }

  jumpToMinute(minute) {
    const dayPoints = this.replayPoints
    if (!dayPoints || dayPoints.length === 0) return

    let targetIndex = 0
    for (let i = 0; i < dayPoints.length; i++) {
      const pointTime = this.parseTimestamp(
        this.replayManager.getTimestamp(dayPoints[i]),
      )
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
    this.replaySegmentDurationMs = this.segmentDurationMs(
      currentPoint,
      nextPoint,
    )
    this.replayLastTime = performance.now()
  }

  prevDay() {
    if (!this.replayManager) return
    this.stopPlayback()
    if (this.replayManager.prevDay()) this.afterDayChange()
  }

  nextDay() {
    if (!this.replayManager) return
    this.stopPlayback()
    if (this.replayManager.nextDay()) this.afterDayChange()
  }

  afterDayChange() {
    this.resetReplayPhotos()
    this.updateDayDisplay()
    this.updateDayCount()
    this.updateDayButtons()
    this.renderDensity()
    this.setInitialScrubberPosition()
    this.clearMarker()
    this.hideCycleControls()
    this.syncAccordion()
  }

  goToDay(dayKey) {
    if (!this.replayManager?.goToDay(dayKey)) return
    this.updateDayDisplay()
    this.updateDayCount()
    this.updateDayButtons()
    this.renderDensity()
  }

  cyclePrev() {
    if (!this.replayManager || !this.c.hasReplayScrubberTarget) return
    const minute = parseInt(this.c.replayScrubberTarget.value, 10)
    this.replayManager.cyclePrev()
    this.afterCycle(minute)
  }

  cycleNext() {
    if (!this.replayManager || !this.c.hasReplayScrubberTarget) return
    const minute = parseInt(this.c.replayScrubberTarget.value, 10)
    this.replayManager.cycleNext(minute)
    this.afterCycle(minute)
  }

  afterCycle(minute) {
    const point = this.replayManager.getPointAtPosition(minute)
    if (!point) return
    this.showMarker(point)
    this.updateSpeedDisplay(this.getPointVelocity(point))
    this.flyToPoint(point)
    this.highlightPoint(point)
    this.updateCycleControls(minute)
  }

  updateDayDisplay() {
    if (!this.c.hasReplayDayDisplayTarget || !this.replayManager) return
    this.c.replayDayDisplayTarget.textContent =
      this.replayManager.getCurrentDayDisplay()
  }

  updateDayButtons() {
    if (!this.replayManager) return
    if (this.c.hasReplayPrevDayButtonTarget) {
      this.c.replayPrevDayButtonTarget.disabled =
        !this.replayManager.canGoPrev()
    }
    if (this.c.hasReplayNextDayButtonTarget) {
      this.c.replayNextDayButtonTarget.disabled =
        !this.replayManager.canGoNext()
    }
  }

  updateTimeDisplay(minute, showNoData = false) {
    if (this.c.hasReplayTimeDisplayTarget) {
      this.c.replayTimeDisplayTarget.textContent =
        ReplayManager.formatMinuteToTime(minute)
    }
    if (this.c.hasReplayDataIndicatorTarget) {
      if (showNoData) {
        this.c.replayDataIndicatorTarget.classList.remove("hidden")
        this.c.replayDataIndicatorTarget.textContent = "No data at this time"
      } else {
        this.c.replayDataIndicatorTarget.classList.add("hidden")
      }
    }
  }

  getPointVelocity(point) {
    if (!point) return null
    if (point.properties?.velocity !== undefined)
      return point.properties.velocity
    if (point.velocity !== undefined) return point.velocity
    return null
  }

  updateSpeedDisplay(velocity) {
    if (!this.c.hasReplaySpeedDisplayTarget) return
    if (velocity !== null && velocity !== undefined && velocity !== "") {
      const speedMs = parseFloat(velocity)
      if (!Number.isNaN(speedMs) && speedMs > 0) {
        this.c.replaySpeedDisplayTarget.textContent = `${Math.round(speedMs * 3.6)} km/h`
        return
      }
    }
    this.c.replaySpeedDisplayTarget.textContent = ""
  }

  updateDayCount() {
    if (!this.c.hasReplayDayCountTarget || !this.replayManager) return
    const dayCount = this.replayManager.getDayCount()
    const currentIndex = this.replayManager.currentDayIndex + 1
    this.c.replayDayCountTarget.textContent = `Day ${currentIndex} of ${dayCount}`
  }

  renderDensity() {
    if (!this.c.hasReplayDensityContainerTarget || !this.replayManager) return
    const container = this.c.replayDensityContainerTarget
    const density = this.replayManager.getDataDensity(48)

    while (container.firstChild) container.removeChild(container.firstChild)

    for (const value of density) {
      const bar = document.createElement("div")
      bar.className = "replay-density-bar"
      if (value > 0) {
        bar.classList.add("has-data")
        if (value > 0.5) bar.classList.add("high-density")
      }
      container.appendChild(bar)
    }
  }

  updateCycleControls(minute) {
    if (!this.c.hasReplayCycleControlsTarget || !this.replayManager) return
    const count = this.replayManager.getPointCountAtMinute(minute)
    if (count > 1) {
      this.c.replayCycleControlsTarget.classList.remove("hidden")
      if (this.c.hasReplayPointCounterTarget) {
        const currentIndex = (this.replayManager.cycleIndex % count) + 1
        this.c.replayPointCounterTarget.textContent = `Point ${currentIndex} of ${count}`
      }
    } else {
      this.c.replayCycleControlsTarget.classList.add("hidden")
    }
  }

  hideCycleControls() {
    if (this.c.hasReplayCycleControlsTarget) {
      this.c.replayCycleControlsTarget.classList.add("hidden")
    }
  }

  togglePlayback() {
    if (this.replayActive) {
      this.stopPlayback()
    } else {
      this.startPlayback()
    }
  }

  speedChange(event) {
    const speeds = [1, 2, 5, 10]
    this.replaySpeed = speeds[parseInt(event.target.value, 10) - 1] || 2
    if (this.c.hasReplaySpeedLabelTarget) {
      this.c.replaySpeedLabelTarget.textContent = `${this.replaySpeed}x`
    }
    this.rescaleSegment()
  }

  rescaleSegment() {
    if (!this.replayActive || !this.replayPoints) return
    const previousDuration = this.replaySegmentDurationMs
    const currentPoint = this.replayPoints[this.replayPointIndex]
    const nextPoint = this.replayPoints[this.replayPointIndex + 1]
    this.replaySegmentDurationMs = this.segmentDurationMs(
      currentPoint,
      nextPoint,
    )
    if (previousDuration > 0) {
      const now = performance.now()
      const progress = Math.min(
        (now - this.replayLastTime) / previousDuration,
        1,
      )
      this.replayLastTime = now - progress * this.replaySegmentDurationMs
    }
  }

  startPlayback() {
    if (this.replayActive) return
    if (!this.replayManager || !this.c.hasReplayScrubberTarget) return

    const currentDay = this.replayManager.getCurrentDay()
    if (!currentDay) return
    const dayPoints = this.replayManager.getPointsForDay(currentDay)
    if (dayPoints.length === 0) return

    this.replayActive = true
    this.replaySpeed = this.replaySpeed || 2
    this.replayPoints = dayPoints
    this.replayPointIndex = 0
    this.userPanned = false
    this.setFollowActive(true)

    const currentMinute = parseInt(this.c.replayScrubberTarget.value, 10)
    for (let i = 0; i < dayPoints.length; i++) {
      const pointTime = this.parseTimestamp(
        this.replayManager.getTimestamp(dayPoints[i]),
      )
      if (pointTime) {
        const date = new Date(pointTime)
        if (date.getHours() * 60 + date.getMinutes() >= currentMinute) {
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
    this.replaySegmentDurationMs = this.segmentDurationMs(startPoint, nextPoint)

    if (startPoint) {
      this.showMarker(startPoint)
      this.flyToPoint(startPoint, true)
      this.highlightPoint(startPoint)
    }

    this.setPlayingState(true)
    this.replayLastTime = performance.now()
    this.frame()
  }

  stopPlayback() {
    if (this.replayActive === undefined) return
    this.replayActive = false
    if (this.replayAnimationId) {
      cancelAnimationFrame(this.replayAnimationId)
      this.replayAnimationId = null
    }
    this.setPlayingState(false)
  }

  setPlayingState(playing) {
    if (this.c.hasReplayPlayButtonTarget) {
      this.c.replayPlayButtonTarget.classList.toggle("playing", playing)
    }
    if (this.c.hasReplayPlayIconTarget) {
      this.c.replayPlayIconTarget.classList.toggle("hidden", playing)
    }
    if (this.c.hasReplayPauseIconTarget) {
      this.c.replayPauseIconTarget.classList.toggle("hidden", !playing)
    }
    if (this.onPlayStateChange) this.onPlayStateChange(playing)
  }

  initPlayback() {
    this.replayActive = false
    this.replaySpeed = 2
    this.replayPoints = []
    this.replayPointIndex = 0
    this.replayLastTime = 0
    this.replayAnimationId = null
    this.replayCurrentCoords = null
    this.replayNextCoords = null
    this.replaySegmentDurationMs = 0
    this.userPanned = false
    this.setFollowActive(false)
    if (this.c.hasReplaySpeedLabelTarget)
      this.c.replaySpeedLabelTarget.textContent = "2x"
    if (this.c.hasReplaySpeedSliderTarget)
      this.c.replaySpeedSliderTarget.value = 2
  }

  segmentDurationMs(currentPoint, nextPoint) {
    const fallback = 500 / this.replaySpeed
    if (!currentPoint || !nextPoint || !this.replayManager) return fallback
    const start = this.parseTimestamp(
      this.replayManager.getTimestamp(currentPoint),
    )
    const end = this.parseTimestamp(this.replayManager.getTimestamp(nextPoint))
    if (!start || !end || end <= start) return fallback
    return Math.min(Math.max((end - start) / (60 * this.replaySpeed), 50), 4000)
  }

  frame() {
    if (!this.replayActive) return

    const now = performance.now()
    const elapsed = now - this.replayLastTime
    const intervalMs = this.replaySegmentDurationMs || 500 / this.replaySpeed
    const progress = Math.min(elapsed / intervalMs, 1)

    if (this.replayCurrentCoords && this.replayNextCoords) {
      const lon =
        this.replayCurrentCoords.lon +
        (this.replayNextCoords.lon - this.replayCurrentCoords.lon) * progress
      const lat =
        this.replayCurrentCoords.lat +
        (this.replayNextCoords.lat - this.replayCurrentCoords.lat) * progress
      this.showMarkerAt(lon, lat)
      this.panToFollow(lon, lat)
    }

    const revealCur = this.replayPoints?.[this.replayPointIndex]
    const revealNext = this.replayPoints?.[this.replayPointIndex + 1]
    if (revealCur) {
      const curTs = this.parseTimestamp(
        this.replayManager.getTimestamp(revealCur),
      )
      const nextTs = revealNext
        ? this.parseTimestamp(this.replayManager.getTimestamp(revealNext))
        : curTs
      this.updateRevealedPhotos(curTs + (nextTs - curTs) * progress)
    }

    if (elapsed >= intervalMs) {
      this.replayLastTime = now
      this.replayPointIndex++

      if (this.replayPointIndex >= this.replayPoints.length) {
        if (this.replayManager.canGoNext()) {
          this.replayManager.nextDay()
          this.updateDayDisplay()
          this.updateDayCount()
          this.renderDensity()
          this.syncAccordion()
          this.replayPoints = this.replayManager.getPointsForDay(
            this.replayManager.getCurrentDay(),
          )
          this.replayPointIndex = 0
          this.resetReplayPhotos()
          if (this.replayPoints.length === 0) return this.stopPlayback()
        } else {
          return this.stopPlayback()
        }
      }

      const currentPoint = this.replayPoints[this.replayPointIndex]
      const nextPoint = this.replayPoints[this.replayPointIndex + 1]
      if (!currentPoint) return this.stopPlayback()

      this.replayCurrentCoords = this.replayManager.getCoordinates(currentPoint)
      this.replayNextCoords = nextPoint
        ? this.replayManager.getCoordinates(nextPoint)
        : this.replayCurrentCoords
      this.replaySegmentDurationMs = this.segmentDurationMs(
        currentPoint,
        nextPoint,
      )
      this.updateSpeedDisplay(this.getPointVelocity(currentPoint))

      const pointTime = this.parseTimestamp(
        this.replayManager.getTimestamp(currentPoint),
      )
      if (pointTime) {
        const date = new Date(pointTime)
        const minute = date.getHours() * 60 + date.getMinutes()
        this.c.replayScrubberTarget.value = minute
        this.updateTimeDisplay(minute, false)
      }

      if (this.replayPointIndex % 5 === 0) this.highlightPoint(currentPoint)
      this.hideCycleControls()
    }

    this.replayAnimationId = requestAnimationFrame(() => this.frame())
  }

  bindFollowInterrupt() {
    if (this._followInterruptBound || !this.map) return
    this._followInterruptBound = true
    this._followEvents = ["mousedown", "touchstart", "wheel", "dragstart"]
    this._followHandler = () => {
      if (!this.userPanned) {
        this.userPanned = true
        this.setFollowActive(false)
      }
    }
    for (const event of this._followEvents) {
      this.map.on(event, this._followHandler)
    }
  }

  unbindFollowInterrupt() {
    if (!this._followInterruptBound || !this.map || !this._followHandler) return
    for (const event of this._followEvents) {
      this.map.off(event, this._followHandler)
    }
    this._followHandler = null
    this._followInterruptBound = false
  }

  panToFollow(lon, lat) {
    if (!this.map || this.userPanned) return
    const center = this.map.getCenter()
    const bounds = this.map.getBounds()
    const lngSpan = bounds.getEast() - bounds.getWest()
    const latSpan = bounds.getNorth() - bounds.getSouth()
    if (lngSpan <= 0 || latSpan <= 0) return

    const lngOffset = Math.abs((lon - center.lng) / lngSpan)
    const latOffset = Math.abs((lat - center.lat) / latSpan)
    if (lngOffset > 0.75 || latOffset > 0.75) {
      this.map.setCenter([lon, lat])
      return
    }

    const ease = 0.08
    this.map.setCenter([
      center.lng + (lon - center.lng) * ease,
      center.lat + (lat - center.lat) * ease,
    ])
  }

  showMarker(point) {
    const coords = this.replayManager?.getCoordinates(point)
    const layer = this.markerLayer
    if (!coords || !layer) return
    this._markerLngLat = [coords.lon, coords.lat]
    layer.showMarker(coords.lon, coords.lat, {
      timestamp: this.replayManager.getTimestamp(point),
    })
  }

  showMarkerAt(lon, lat) {
    if (lon === undefined || lat === undefined) return
    this._markerLngLat = [lon, lat]
    const layer = this.markerLayer
    if (layer) layer.showMarker(lon, lat)
  }

  recenterFollow() {
    this.userPanned = false
    this.setFollowActive(true)
    if (this.map && this._markerLngLat) {
      this.map.easeTo({ center: this._markerLngLat, duration: 400 })
    }
  }

  setFollowActive(active) {
    if (!this.c.hasReplayFollowButtonTarget) return
    this.c.replayFollowButtonTarget.classList.toggle("following", active)
  }

  clearMarker() {
    const layer = this.markerLayer
    if (layer) layer.clear()
  }

  highlightPoint(point) {
    if (this._highlightPoint) this._highlightPoint(point)
  }

  clearHighlight() {
    if (this._clearHighlight) this._clearHighlight()
  }

  flyToPoint(point, fast = false) {
    const coords = this.replayManager?.getCoordinates(point)
    if (!coords || !this.map) return
    this.map.flyTo({
      center: [coords.lon, coords.lat],
      zoom: Math.max(this.map.getZoom(), 14),
      duration: fast ? 100 : 500,
    })
  }

  parseTimestamp(timestamp) {
    if (!timestamp) return 0
    if (typeof timestamp === "string") return new Date(timestamp).getTime()
    if (typeof timestamp === "number")
      return timestamp < 10000000000 ? timestamp * 1000 : timestamp
    return 0
  }

  syncToDay(dayKey) {
    if (!this.replayManager || !this.isOpen) return
    this.stopPlayback()
    if (this.replayManager.goToDay(dayKey)) {
      this.resetReplayPhotos()
      this.updateDayDisplay()
      this.updateDayCount()
      this.updateDayButtons()
      this.renderDensity()
      this.setInitialScrubberPosition()
      this.clearMarker()
      this.hideCycleControls()
    }
  }

  syncAccordion() {
    if (!this.replayManager) return
    const currentDay = this.replayManager.getCurrentDay()
    if (!currentDay) return

    if (this.onDaySync) {
      this.onDaySync(currentDay)
      return
    }

    if (!this.element) return

    for (const row of this.element.querySelectorAll("[data-day-key]")) {
      const isCurrent = row.dataset.dayKey === currentDay
      if (row.tagName === "DETAILS") {
        if (isCurrent) {
          row.setAttribute("open", "")
        } else {
          row.removeAttribute("open")
        }
      }
      row.classList.toggle("ring-2", isCurrent)
      row.classList.toggle("ring-primary", isCurrent)
      if (isCurrent)
        row.scrollIntoView({ behavior: "smooth", block: "nearest" })
    }

    if (this.dayRoutesLayer) this.dayRoutesLayer.selectDay(currentDay)
  }

  setButtonActive(active) {
    if (!this.c.hasReplayToggleBtnTarget) return
    const button = this.c.replayToggleBtnTarget
    if (active) {
      button.classList.remove("btn-outline")
      button.classList.add("btn-active", "btn-primary")
    } else {
      button.classList.remove("btn-active", "btn-primary")
      button.classList.add("btn-outline")
    }
  }
}
