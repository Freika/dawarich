/**
 * TimelineManager - Core business logic for timeline feature
 * Manages point data grouping by day, indexing by minute, and navigation state
 */
export class TimelineManager {
  constructor(options = {}) {
    this.timezone = options.timezone || "UTC"
    this.points = []
    this.pointsByDay = {} // { '2025-01-15': [point1, ...] }
    this.availableDays = [] // ['2025-01-15', '2025-01-16']
    this.currentDayIndex = 0
    this.pointsByMinute = {} // { 480: [point1, point2] } for current day
    this.minutesWithData = new Set() // Set of minutes that have data
    this.pinnedPoint = null
    this.cycleIndex = 0 // For multi-point minutes
    this.onStateChange = options.onStateChange || (() => {})
  }

  /**
   * Set points and process them into day/minute groups
   * @param {Array} points - Array of point objects with timestamp and coordinates
   */
  setPoints(points) {
    this.points = points || []
    this.groupPointsByDay()
    this.currentDayIndex = 0
    this.pinnedPoint = null
    this.cycleIndex = 0
    this.buildMinuteIndex()
  }

  /**
   * Parse timestamp to Date object, handling various formats
   * @private
   */
  _parseTimestamp(timestamp) {
    if (!timestamp) return null

    // Handle ISO 8601 string
    if (typeof timestamp === "string") {
      return new Date(timestamp)
    }

    // Handle Unix timestamp
    if (typeof timestamp === "number") {
      // Unix timestamp in seconds (< year 2286 in seconds)
      if (timestamp < 10000000000) {
        return new Date(timestamp * 1000)
      }
      // Unix timestamp in milliseconds
      return new Date(timestamp)
    }

    return null
  }

  /**
   * Group points by calendar day (in user's timezone)
   */
  groupPointsByDay() {
    this.pointsByDay = {}

    this.points.forEach((point) => {
      const timestamp = this._getTimestamp(point)
      if (!timestamp) return

      const date = this._parseTimestamp(timestamp)
      if (!date || Number.isNaN(date.getTime())) return

      const dayKey = this._formatDayKey(date)

      if (!this.pointsByDay[dayKey]) {
        this.pointsByDay[dayKey] = []
      }
      this.pointsByDay[dayKey].push(point)
    })

    // Sort days chronologically
    this.availableDays = Object.keys(this.pointsByDay).sort()

    // Sort points within each day by timestamp
    this.availableDays.forEach((day) => {
      this.pointsByDay[day].sort((a, b) => {
        const tsA = this._parseTimestamp(this._getTimestamp(a))?.getTime() || 0
        const tsB = this._parseTimestamp(this._getTimestamp(b))?.getTime() || 0
        return tsA - tsB
      })
    })
  }

  /**
   * Build minute index for current day (0-1439 minutes)
   */
  buildMinuteIndex() {
    this.pointsByMinute = {}
    this.minutesWithData = new Set()

    const currentDay = this.getCurrentDay()
    if (!currentDay) return

    const dayPoints = this.pointsByDay[currentDay] || []

    dayPoints.forEach((point) => {
      const timestamp = this._getTimestamp(point)
      if (!timestamp) return

      const date = this._parseTimestamp(timestamp)
      if (!date || Number.isNaN(date.getTime())) return

      const minuteOfDay = date.getHours() * 60 + date.getMinutes()

      if (!this.pointsByMinute[minuteOfDay]) {
        this.pointsByMinute[minuteOfDay] = []
      }
      this.pointsByMinute[minuteOfDay].push(point)
      this.minutesWithData.add(minuteOfDay)
    })
  }

  /**
   * Get array of minute ranges that have data
   * Each range is { start: number, end: number }
   * Used for rendering data density on scrubber
   * @returns {Array} Array of {start, end} objects
   */
  getDataRanges() {
    if (this.minutesWithData.size === 0) return []

    const sortedMinutes = Array.from(this.minutesWithData).sort((a, b) => a - b)
    const ranges = []
    let rangeStart = sortedMinutes[0]
    let rangeEnd = sortedMinutes[0]

    for (let i = 1; i < sortedMinutes.length; i++) {
      const minute = sortedMinutes[i]
      // If gap is more than 5 minutes, start a new range
      if (minute - rangeEnd > 5) {
        ranges.push({ start: rangeStart, end: rangeEnd })
        rangeStart = minute
      }
      rangeEnd = minute
    }
    // Push the last range
    ranges.push({ start: rangeStart, end: rangeEnd })

    return ranges
  }

  /**
   * Get data density for scrubber visualization (0-1 values per segment)
   * @param {number} segments - Number of segments to divide the day into
   * @returns {Array} Array of density values (0-1)
   */
  getDataDensity(segments = 48) {
    const density = new Array(segments).fill(0)
    const minutesPerSegment = 1440 / segments

    this.minutesWithData.forEach((minute) => {
      const segmentIndex = Math.floor(minute / minutesPerSegment)
      if (segmentIndex < segments) {
        density[segmentIndex]++
      }
    })

    // Normalize to 0-1
    const maxDensity = Math.max(...density, 1)
    return density.map((d) => d / maxDensity)
  }

  /**
   * Check if a minute has data
   * @param {number} minute - Minute of day (0-1439)
   * @returns {boolean}
   */
  hasDataAtMinute(minute) {
    return this.minutesWithData.has(minute)
  }

  /**
   * Get current day key
   * @returns {string|null} Day key like '2025-01-15'
   */
  getCurrentDay() {
    if (this.availableDays.length === 0) return null
    return this.availableDays[this.currentDayIndex] || null
  }

  /**
   * Get formatted display string for current day
   * @returns {string} Display string like 'January 15, 2025'
   */
  getCurrentDayDisplay() {
    const day = this.getCurrentDay()
    if (!day) return "No data"

    const [year, month, dayNum] = day.split("-").map(Number)
    const date = new Date(year, month - 1, dayNum)

    return date.toLocaleDateString("en-US", {
      year: "numeric",
      month: "long",
      day: "numeric",
    })
  }

  /**
   * Get points at a specific minute of the day
   * @param {number} minute - Minute of day (0-1439)
   * @returns {Array} Points at that minute
   */
  getPointsAtMinute(minute) {
    return this.pointsByMinute[minute] || []
  }

  /**
   * Find nearest minute with points (forward search first, then backward)
   * @param {number} minute - Starting minute
   * @returns {number|null} Nearest minute with points, or null if none
   */
  findNearestMinuteWithPoints(minute) {
    if (this.minutesWithData.size === 0) return null

    // Check current minute first
    if (this.minutesWithData.has(minute)) return minute

    // Search outward from target minute
    const maxMinute = 1439
    for (let offset = 1; offset <= maxMinute; offset++) {
      // Check forward
      if (
        minute + offset <= maxMinute &&
        this.minutesWithData.has(minute + offset)
      ) {
        return minute + offset
      }
      // Check backward
      if (minute - offset >= 0 && this.minutesWithData.has(minute - offset)) {
        return minute - offset
      }
    }

    return null
  }

  /**
   * Get point at current position (respecting cycle index for multi-point minutes)
   * @param {number} minute - Minute of day
   * @returns {Object|null} Point object or null
   */
  getPointAtPosition(minute) {
    const points = this.getPointsAtMinute(minute)
    if (points.length === 0) return null

    const index = this.cycleIndex % points.length
    return points[index]
  }

  /**
   * Get total number of points at a minute
   * @param {number} minute - Minute of day
   * @returns {number} Count of points
   */
  getPointCountAtMinute(minute) {
    return this.getPointsAtMinute(minute).length
  }

  /**
   * Pin a point (lock selection)
   * @param {Object} point - Point to pin
   */
  pinPoint(point) {
    this.pinnedPoint = point
    this.onStateChange({ type: "pin", point })
  }

  /**
   * Unpin current point
   */
  unpinPoint() {
    this.pinnedPoint = null
    this.cycleIndex = 0
    this.onStateChange({ type: "unpin" })
  }

  /**
   * Check if a point is currently pinned
   * @returns {boolean}
   */
  isPinned() {
    return this.pinnedPoint !== null
  }

  /**
   * Navigate to previous day
   * @returns {boolean} Whether navigation was successful
   */
  prevDay() {
    if (this.currentDayIndex > 0) {
      this.currentDayIndex--
      this.buildMinuteIndex()
      this.cycleIndex = 0
      this.pinnedPoint = null
      return true
    }
    return false
  }

  /**
   * Navigate to next day
   * @returns {boolean} Whether navigation was successful
   */
  nextDay() {
    if (this.currentDayIndex < this.availableDays.length - 1) {
      this.currentDayIndex++
      this.buildMinuteIndex()
      this.cycleIndex = 0
      this.pinnedPoint = null
      return true
    }
    return false
  }

  /**
   * Check if previous day navigation is available
   * @returns {boolean}
   */
  canGoPrev() {
    return this.currentDayIndex > 0
  }

  /**
   * Check if next day navigation is available
   * @returns {boolean}
   */
  canGoNext() {
    return this.currentDayIndex < this.availableDays.length - 1
  }

  /**
   * Cycle to previous point in multi-point minute
   */
  cyclePrev() {
    this.cycleIndex = Math.max(0, this.cycleIndex - 1)
  }

  /**
   * Cycle to next point in multi-point minute
   * @param {number} minute - Current minute (to get count)
   */
  cycleNext(minute) {
    const count = this.getPointCountAtMinute(minute)
    if (count > 0) {
      this.cycleIndex = (this.cycleIndex + 1) % count
    }
  }

  /**
   * Reset cycle index
   */
  resetCycle() {
    this.cycleIndex = 0
  }

  /**
   * Get number of days available
   * @returns {number}
   */
  getDayCount() {
    return this.availableDays.length
  }

  /**
   * Check if timeline has data
   * @returns {boolean}
   */
  hasData() {
    return this.availableDays.length > 0
  }

  /**
   * Get total points on current day
   * @returns {number}
   */
  getCurrentDayPointCount() {
    const day = this.getCurrentDay()
    if (!day) return 0
    return this.pointsByDay[day]?.length || 0
  }

  /**
   * Format minute of day to time string
   * @param {number} minute - Minute of day (0-1439)
   * @returns {string} Time string like '08:30'
   */
  static formatMinuteToTime(minute) {
    const hours = Math.floor(minute / 60)
    const mins = minute % 60
    return `${hours.toString().padStart(2, "0")}:${mins.toString().padStart(2, "0")}`
  }

  /**
   * Find transportation mode emoji for a point by matching its timestamp to track time ranges
   * @param {Object} point - Point object with timestamp
   * @param {Object} tracksGeoJSON - GeoJSON FeatureCollection of tracks
   * @returns {string|null} Emoji for transportation mode, or null if not found
   */
  static findTransportationEmoji(point, tracksGeoJSON) {
    if (!tracksGeoJSON?.features?.length) return null

    const timestamp = TimelineManager._getTimestampStatic(point)
    if (!timestamp) return null

    const pointTime = TimelineManager._parseTimestampStatic(timestamp)
    if (!pointTime) return null

    // Convert pointTime to seconds for segment matching
    const pointTimeSec = Math.floor(pointTime / 1000)

    for (const track of tracksGeoJSON.features) {
      const startAt = track.properties?.start_at
      const endAt = track.properties?.end_at

      if (startAt && endAt) {
        const trackStart = new Date(startAt).getTime()
        const trackEnd = new Date(endAt).getTime()

        if (pointTime >= trackStart && pointTime <= trackEnd) {
          // Try per-segment matching first (mode_timeline has start_time/end_time in unix seconds)
          const modeTimeline = track.properties?.mode_timeline
          if (modeTimeline?.length) {
            for (const seg of modeTimeline) {
              if (
                pointTimeSec >= seg.start_time &&
                pointTimeSec <= seg.end_time
              ) {
                return seg.emoji || null
              }
            }

            // Nearest-segment fallback: find last segment whose start_time <= pointTime
            let nearest = null
            for (const seg of modeTimeline) {
              if (seg.start_time <= pointTimeSec) {
                nearest = seg
              }
            }
            if (nearest?.emoji) return nearest.emoji
          }

          // Fall back to track-level dominant mode
          return track.properties.dominant_mode_emoji || null
        }
      }
    }
    return null
  }

  /**
   * Static version of _getTimestamp for use in static methods
   * @private
   */
  static _getTimestampStatic(point) {
    // Handle GeoJSON feature format
    if (point.properties?.timestamp) {
      return point.properties.timestamp
    }
    // Handle raw point format
    if (point.timestamp) {
      return point.timestamp
    }
    return null
  }

  /**
   * Static version of _parseTimestamp for use in static methods
   * Returns timestamp as milliseconds
   * @private
   */
  static _parseTimestampStatic(timestamp) {
    if (!timestamp) return null

    // Handle ISO 8601 string
    if (typeof timestamp === "string") {
      const date = new Date(timestamp)
      return Number.isNaN(date.getTime()) ? null : date.getTime()
    }

    // Handle Unix timestamp
    if (typeof timestamp === "number") {
      // Unix timestamp in seconds (< year 2286 in seconds)
      if (timestamp < 10000000000) {
        return timestamp * 1000
      }
      // Unix timestamp in milliseconds
      return timestamp
    }

    return null
  }

  // Private helpers

  /**
   * Get timestamp from point (handles different point formats)
   * @private
   */
  _getTimestamp(point) {
    // Handle GeoJSON feature format
    if (point.properties?.timestamp) {
      return point.properties.timestamp
    }
    // Handle raw point format
    if (point.timestamp) {
      return point.timestamp
    }
    return null
  }

  /**
   * Format date to day key
   * @private
   */
  _formatDayKey(date) {
    const year = date.getFullYear()
    const month = (date.getMonth() + 1).toString().padStart(2, "0")
    const day = date.getDate().toString().padStart(2, "0")
    return `${year}-${month}-${day}`
  }

  /**
   * Get coordinates from point
   * @param {Object} point - Point object
   * @returns {Object|null} { lon, lat } or null
   */
  getCoordinates(point) {
    if (!point) return null

    let lon, lat

    // Handle GeoJSON feature format
    if (point.geometry?.coordinates) {
      lon = point.geometry.coordinates[0]
      lat = point.geometry.coordinates[1]
    }
    // Handle raw point format with longitude/latitude
    else if (point.longitude !== undefined && point.latitude !== undefined) {
      lon = point.longitude
      lat = point.latitude
    }
    // Handle raw point format with lon/lat
    else if (point.lon !== undefined && point.lat !== undefined) {
      lon = point.lon
      lat = point.lat
    } else {
      return null
    }

    // Ensure coordinates are numbers (not strings) for arithmetic operations
    return {
      lon: Number(lon),
      lat: Number(lat),
    }
  }
}
