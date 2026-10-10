import { translate } from "i18n"
import { ReplayDayClock } from "maps_maplibre/managers/replay_day_clock"
import * as pointUtils from "maps_maplibre/managers/replay_point_utils"

/**
 * ReplayManager - Core business logic for replay feature
 * Manages point data grouping by day, indexing by minute, and navigation state
 */
export class ReplayManager {
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
    this.dayClock = new ReplayDayClock(this.timezone)
  }

  /**
   * Set points and process them into day/minute groups
   * @param {Array} points - Array of point objects with timestamp and coordinates
   */
  setPoints(points) {
    this.points = points || []
    this.dayClock.clear()
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
    return pointUtils.parseTimestamp(timestamp)
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

      const parts = this._getDateParts(date)
      if (!parts) return

      const dayKey = this._formatDayKey(parts)

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

      const minuteOfDay = this.minuteOfDay(date)
      if (minuteOfDay === null) return

      if (!this.pointsByMinute[minuteOfDay]) {
        this.pointsByMinute[minuteOfDay] = []
      }
      this.pointsByMinute[minuteOfDay].push(point)
      this.minutesWithData.add(minuteOfDay)
    })
  }

  minuteOfDay(date) {
    return this.dayClock.minuteOfDay(date)
  }

  getCurrentDayLengthMinutes() {
    const day = this.getCurrentDay()
    return day ? this.dayClock._getDayBounds(day).length : 1440
  }

  formatCurrentMinute(minute) {
    const day = this.getCurrentDay()
    if (!day) return ReplayManager.formatMinuteToTime(minute)
    return this.dayClock.formatMinute(day, minute)
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
    return this.dayClock.dataDensity(
      this.minutesWithData,
      this.getCurrentDayLengthMinutes(),
      segments,
    )
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
    if (!day) return translate("replay.no_data")

    const [year, month, dayNum] = day.split("-").map(Number)
    const date = new Date(year, month - 1, dayNum)

    return date.toLocaleDateString(document.documentElement.lang || undefined, {
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
    return this.dayClock.nearestMinuteWithPoints(
      this.minutesWithData,
      minute,
      this.getCurrentDayLengthMinutes(),
    )
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
   * Navigate to a specific day by key
   * @param {string} dayKey - Day key like '2025-01-15'
   * @returns {boolean} Whether navigation was successful
   */
  goToDay(dayKey) {
    const index = this.availableDays.indexOf(dayKey)
    if (index === -1 || index === this.currentDayIndex) return false

    this.currentDayIndex = index
    this.buildMinuteIndex()
    this.cycleIndex = 0
    this.pinnedPoint = null
    return true
  }

  /**
   * Get points for a specific day
   * @param {string} dayKey - Day key like '2025-01-15'
   * @returns {Array} Points for that day, or empty array
   */
  getPointsForDay(dayKey) {
    return this.pointsByDay[dayKey] || []
  }

  /**
   * Get timestamp from point (handles different point formats)
   * @param {Object} point - Point object
   * @returns {number|string|null}
   */
  getTimestamp(point) {
    return this._getTimestamp(point)
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
   * Check if replay has data
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
    return pointUtils.findTransportationEmoji(point, tracksGeoJSON)
  }

  /**
   * Static version of _getTimestamp for use in static methods
   * @private
   */
  static _getTimestampStatic(point) {
    return pointUtils.getTimestamp(point)
  }

  /**
   * Static version of _parseTimestamp for use in static methods
   * Returns timestamp as milliseconds
   * @private
   */
  static _parseTimestampStatic(timestamp) {
    const date = pointUtils.parseTimestamp(timestamp)
    return date && !Number.isNaN(date.getTime()) ? date.getTime() : null
  }

  // Private helpers

  /**
   * Get timestamp from point (handles different point formats)
   * @private
   */
  _getTimestamp(point) {
    return pointUtils.getTimestamp(point)
  }

  _getDateParts(date) {
    return this.dayClock._getDateParts(date)
  }

  _formatDayKey(parts) {
    return this.dayClock._formatDayKey(parts)
  }

  _getDayBounds(dayKey) {
    return this.dayClock._getDayBounds(dayKey)
  }

  _localMidnightInstant(year, month, day) {
    return this.dayClock._localMidnightInstant(year, month, day)
  }

  _sameClockTime(first, second) {
    return this.dayClock._sameClockTime(first, second)
  }

  _timeZoneName(date) {
    return this.dayClock._timeZoneName(date)
  }

  /**
   * Get coordinates from point
   * @param {Object} point - Point object
   * @returns {Object|null} { lon, lat } or null
   */
  getCoordinates(point) {
    return pointUtils.getCoordinates(point)
  }
}
