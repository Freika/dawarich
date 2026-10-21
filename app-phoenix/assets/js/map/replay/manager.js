import { ReplayDayClock } from "./day_clock.js"
import * as pointUtils from "./point_utils.js"

export class ReplayManager {
  constructor(options = {}) {
    this.timezone = options.timezone || "UTC"
    this.locale = options.locale
    this.noDataLabel = options.noDataLabel || ""
    this.points = []
    this.pointsByDay = {}
    this.availableDays = []
    this.currentDayIndex = 0
    this.pointsByMinute = {}
    this.minutesWithData = new Set()
    this.pinnedPoint = null
    this.cycleIndex = 0
    this.onStateChange = options.onStateChange || (() => {})
    this.dayClock = new ReplayDayClock(this.timezone)
  }

  setPoints(points) {
    this.points = points || []
    this.dayClock.clear()
    this.groupPointsByDay()
    this.currentDayIndex = 0
    this.pinnedPoint = null
    this.cycleIndex = 0
    this.buildMinuteIndex()
  }

  _parseTimestamp(timestamp) {
    return pointUtils.parseTimestamp(timestamp)
  }

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

    this.availableDays = Object.keys(this.pointsByDay).sort()

    this.availableDays.forEach((day) => {
      this.pointsByDay[day].sort((a, b) => {
        const tsA = this._parseTimestamp(this._getTimestamp(a))?.getTime() || 0
        const tsB = this._parseTimestamp(this._getTimestamp(b))?.getTime() || 0
        return tsA - tsB
      })
    })
  }

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

  getDataRanges() {
    if (this.minutesWithData.size === 0) return []

    const sortedMinutes = Array.from(this.minutesWithData).sort((a, b) => a - b)
    const ranges = []
    let rangeStart = sortedMinutes[0]
    let rangeEnd = sortedMinutes[0]

    for (let i = 1; i < sortedMinutes.length; i++) {
      const minute = sortedMinutes[i]
      if (minute - rangeEnd > 5) {
        ranges.push({ start: rangeStart, end: rangeEnd })
        rangeStart = minute
      }
      rangeEnd = minute
    }
    ranges.push({ start: rangeStart, end: rangeEnd })

    return ranges
  }

  getDataDensity(segments = 48) {
    return this.dayClock.dataDensity(
      this.minutesWithData,
      this.getCurrentDayLengthMinutes(),
      segments,
    )
  }

  hasDataAtMinute(minute) {
    return this.minutesWithData.has(minute)
  }

  getCurrentDay() {
    if (this.availableDays.length === 0) return null
    return this.availableDays[this.currentDayIndex] || null
  }

  getCurrentDayDisplay() {
    const day = this.getCurrentDay()
    if (!day) return this.noDataLabel

    const [year, month, dayNum] = day.split("-").map(Number)
    const date = new Date(year, month - 1, dayNum)

    return date.toLocaleDateString(this.locale || undefined, {
      year: "numeric",
      month: "long",
      day: "numeric",
    })
  }

  getPointsAtMinute(minute) {
    return this.pointsByMinute[minute] || []
  }

  findNearestMinuteWithPoints(minute) {
    return this.dayClock.nearestMinuteWithPoints(
      this.minutesWithData,
      minute,
      this.getCurrentDayLengthMinutes(),
    )
  }

  getPointAtPosition(minute) {
    const points = this.getPointsAtMinute(minute)
    if (points.length === 0) return null

    const index = this.cycleIndex % points.length
    return points[index]
  }

  getPointCountAtMinute(minute) {
    return this.getPointsAtMinute(minute).length
  }

  pinPoint(point) {
    this.pinnedPoint = point
    this.onStateChange({ type: "pin", point })
  }

  unpinPoint() {
    this.pinnedPoint = null
    this.cycleIndex = 0
    this.onStateChange({ type: "unpin" })
  }

  isPinned() {
    return this.pinnedPoint !== null
  }

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

  canGoPrev() {
    return this.currentDayIndex > 0
  }

  canGoNext() {
    return this.currentDayIndex < this.availableDays.length - 1
  }

  goToDay(dayKey) {
    const index = this.availableDays.indexOf(dayKey)
    if (index === -1 || index === this.currentDayIndex) return false

    this.currentDayIndex = index
    this.buildMinuteIndex()
    this.cycleIndex = 0
    this.pinnedPoint = null
    return true
  }

  getPointsForDay(dayKey) {
    return this.pointsByDay[dayKey] || []
  }

  getTimestamp(point) {
    return this._getTimestamp(point)
  }

  cyclePrev() {
    this.cycleIndex = Math.max(0, this.cycleIndex - 1)
  }

  cycleNext(minute) {
    const count = this.getPointCountAtMinute(minute)
    if (count > 0) {
      this.cycleIndex = (this.cycleIndex + 1) % count
    }
  }

  resetCycle() {
    this.cycleIndex = 0
  }

  getDayCount() {
    return this.availableDays.length
  }

  hasData() {
    return this.availableDays.length > 0
  }

  getCurrentDayPointCount() {
    const day = this.getCurrentDay()
    if (!day) return 0
    return this.pointsByDay[day]?.length || 0
  }

  static formatMinuteToTime(minute) {
    const hours = Math.floor(minute / 60)
    const mins = minute % 60
    return `${hours.toString().padStart(2, "0")}:${mins.toString().padStart(2, "0")}`
  }

  _getTimestamp(point) {
    return pointUtils.getTimestamp(point)
  }

  _getDateParts(date) {
    return this.dayClock._getDateParts(date)
  }

  _formatDayKey(parts) {
    return this.dayClock._formatDayKey(parts)
  }

  getCoordinates(point) {
    return pointUtils.getCoordinates(point)
  }
}
