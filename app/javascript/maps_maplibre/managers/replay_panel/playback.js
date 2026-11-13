/**
 * Replay playback: play/pause, speed, segment timing and the animation frame.
 * Mixed into ReplayPanel; `this` is the ReplayPanel.
 */
export const playback = {
  togglePlayback() {
    if (this.replayActive) {
      this.stopPlayback()
    } else {
      this.startPlayback()
    }
  },

  speedChange(event) {
    const speeds = [1, 2, 5, 10]
    this.replaySpeed = speeds[parseInt(event.target.value, 10) - 1] || 2
    if (this.c.hasReplaySpeedLabelTarget) {
      this.c.replaySpeedLabelTarget.textContent = `${this.replaySpeed}x`
    }
    this.rescaleSegment()
  },

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
  },

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

    const currentMinute = this.scrubberMinute
    for (let i = 0; i < dayPoints.length; i++) {
      const pointTime = this.parseTimestamp(
        this.replayManager.getTimestamp(dayPoints[i]),
      )
      if (pointTime) {
        const date = new Date(pointTime)
        if (this.replayManager.minuteOfDay(date) >= currentMinute) {
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
  },

  stopPlayback() {
    if (this.replayActive === undefined) return
    this.replayActive = false
    if (this.replayAnimationId) {
      cancelAnimationFrame(this.replayAnimationId)
      this.replayAnimationId = null
    }
    this.setPlayingState(false)
  },

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
  },

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
  },

  segmentDurationMs(currentPoint, nextPoint) {
    const fallback = 500 / this.replaySpeed
    if (!currentPoint || !nextPoint || !this.replayManager) return fallback
    const start = this.parseTimestamp(
      this.replayManager.getTimestamp(currentPoint),
    )
    const end = this.parseTimestamp(this.replayManager.getTimestamp(nextPoint))
    if (!start || !end || end <= start) return fallback
    return Math.min(Math.max((end - start) / (60 * this.replaySpeed), 50), 4000)
  },

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
        const minute = this.replayManager.minuteOfDay(date)
        this.setScrubber(minute)
        this.updateTimeDisplay(minute, false)
      }

      if (this.replayPointIndex % 5 === 0) this.highlightPoint(currentPoint)
      this.hideCycleControls()
    }

    this.replayAnimationId = requestAnimationFrame(() => this.frame())
  },
}
