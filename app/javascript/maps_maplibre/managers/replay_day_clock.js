export class ReplayDayClock {
  constructor(timezone = "UTC") {
    this.timezone = timezone
    this.dayBounds = {}
  }

  clear() {
    this.dayBounds = {}
  }

  _getDateParts(date) {
    if (!date || Number.isNaN(date.getTime())) return null

    try {
      const formatter = new Intl.DateTimeFormat("en-US", {
        timeZone: this.timezone || "UTC",
        year: "numeric",
        month: "2-digit",
        day: "2-digit",
        hour: "2-digit",
        minute: "2-digit",
        hourCycle: "h23",
      })
      const parts = formatter.formatToParts(date).reduce((acc, part) => {
        if (part.type !== "literal") acc[part.type] = part.value
        return acc
      }, {})

      return {
        year: parseInt(parts.year, 10),
        month: parseInt(parts.month, 10),
        day: parseInt(parts.day, 10),
        hour: parseInt(parts.hour, 10),
        minute: parseInt(parts.minute, 10),
      }
    } catch (_err) {
      return {
        year: date.getFullYear(),
        month: date.getMonth() + 1,
        day: date.getDate(),
        hour: date.getHours(),
        minute: date.getMinutes(),
      }
    }
  }

  _formatDayKey({ year, month, day }) {
    const mm = month.toString().padStart(2, "0")
    const dd = day.toString().padStart(2, "0")
    return `${year}-${mm}-${dd}`
  }

  _getDayBounds(dayKey) {
    if (this.dayBounds[dayKey]) return this.dayBounds[dayKey]

    const [year, month, day] = dayKey.split("-").map(Number)
    const start = this._localMidnightInstant(year, month, day)
    const nextDate = new Date(Date.UTC(year, month - 1, day + 1))
    const next = this._localMidnightInstant(
      nextDate.getUTCFullYear(),
      nextDate.getUTCMonth() + 1,
      nextDate.getUTCDate(),
    )
    const bounds = { start, length: Math.round((next - start) / 60000) }
    this.dayBounds[dayKey] = bounds
    return bounds
  }

  _localMidnightInstant(year, month, day) {
    const target = Date.UTC(year, month - 1, day)
    let instant = target
    for (let i = 0; i < 3; i++) {
      const parts = this._getDateParts(new Date(instant))
      const actual = Date.UTC(
        parts.year,
        parts.month - 1,
        parts.day,
        parts.hour,
        parts.minute,
      )
      const delta = target - actual
      if (delta === 0) return instant
      instant += delta
    }
    return instant
  }

  _sameClockTime(first, second) {
    return (
      second &&
      first.year === second.year &&
      first.month === second.month &&
      first.day === second.day &&
      first.hour === second.hour &&
      first.minute === second.minute
    )
  }

  _timeZoneName(date) {
    try {
      return new Intl.DateTimeFormat("en-US", {
        timeZone: this.timezone || "UTC",
        timeZoneName: "short",
      })
        .formatToParts(date)
        .find((part) => part.type === "timeZoneName")?.value
    } catch (_err) {
      return ""
    }
  }

  minuteOfDay(date) {
    const parts = this._getDateParts(date)
    if (!parts) return null
    const bounds = this._getDayBounds(this._formatDayKey(parts))
    return Math.floor((date.getTime() - bounds.start) / 60000)
  }

  dataDensity(minutesWithData, dayLength, segments = 48) {
    const density = new Array(segments).fill(0)
    const minutesPerSegment = dayLength / segments

    minutesWithData.forEach((minute) => {
      const segmentIndex = Math.floor(minute / minutesPerSegment)
      if (segmentIndex < segments) density[segmentIndex]++
    })

    const maxDensity = Math.max(...density, 1)
    return density.map((value) => value / maxDensity)
  }

  nearestMinuteWithPoints(minutesWithData, minute, dayLength) {
    if (minutesWithData.size === 0) return null
    if (minutesWithData.has(minute)) return minute

    const maxMinute = dayLength - 1
    for (let offset = 1; offset <= maxMinute; offset++) {
      if (
        minute + offset <= maxMinute &&
        minutesWithData.has(minute + offset)
      ) {
        return minute + offset
      }
      if (minute - offset >= 0 && minutesWithData.has(minute - offset)) {
        return minute - offset
      }
    }

    return null
  }

  formatMinute(day, minute) {
    const date = new Date(this._getDayBounds(day).start + minute * 60000)
    const parts = this._getDateParts(date)
    if (!parts) return null

    const time = `${parts.hour.toString().padStart(2, "0")}:${parts.minute
      .toString()
      .padStart(2, "0")}`
    const previous = this._getDateParts(new Date(date.getTime() - 3600000))
    const next = this._getDateParts(new Date(date.getTime() + 3600000))
    if (
      (this._sameClockTime(parts, previous) ||
        this._sameClockTime(parts, next)) &&
      this._formatDayKey(parts) === day
    ) {
      const zone = this._timeZoneName(date)
      return zone ? `${time} ${zone}` : time
    }
    return time
  }
}
