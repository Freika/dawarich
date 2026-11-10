import { ReplayMarkerLayer } from "maps_maplibre/layers/replay_marker_layer"
import { ReplayManager } from "maps_maplibre/managers/replay_manager"
import { displays } from "./replay_panel/displays"
import { photos } from "./replay_panel/photos"
import { playback } from "./replay_panel/playback"

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

Object.assign(ReplayPanel.prototype, playback, displays, photos)
