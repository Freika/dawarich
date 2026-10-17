/**
 * Manages date formatting and range calculations
 */
export class DateManager {
  static dayInTimeZone(isoString, timeZone) {
    if (!isoString) return null
    if (!timeZone) return isoString.slice(0, 10)

    return DateManager.formatDateForAPI(new Date(isoString), timeZone).slice(
      0,
      10,
    )
  }

  static formatDateForAPI(date, timeZone) {
    const pad = (n) => String(n).padStart(2, "0")
    let year = date.getFullYear()
    let month = pad(date.getMonth() + 1)
    let day = pad(date.getDate())
    let hours = pad(date.getHours())
    let minutes = pad(date.getMinutes())
    let seconds = pad(date.getSeconds())
    let tzOffset = -date.getTimezoneOffset()

    if (timeZone) {
      let parts
      try {
        parts = new Intl.DateTimeFormat("en-US", {
          timeZone,
          year: "numeric",
          month: "2-digit",
          day: "2-digit",
          hour: "2-digit",
          minute: "2-digit",
          second: "2-digit",
          hourCycle: "h23",
        }).formatToParts(date)
      } catch {
        return DateManager.formatDateForAPI(date)
      }
      const values = Object.fromEntries(
        parts.map(({ type, value }) => [type, value]),
      )
      year = Number(values.year)
      month = values.month
      day = values.day
      hours = values.hour
      minutes = values.minute
      seconds = values.second
      tzOffset =
        Date.UTC(
          year,
          Number(month) - 1,
          Number(day),
          Number(hours),
          Number(minutes),
        ) /
          60000 -
        Math.floor(date.getTime() / 60000)
    }

    const tzSign = tzOffset >= 0 ? "+" : "-"
    const tzHours = pad(Math.floor(Math.abs(tzOffset) / 60))
    const tzMinutes = pad(Math.abs(tzOffset) % 60)

    return `${year}-${month}-${day}T${hours}:${minutes}:${seconds}${tzSign}${tzHours}:${tzMinutes}`
  }

  static formatLocalDateForAPI(value, timeZone) {
    const parsed = new Date(value)
    if (Number.isNaN(parsed.getTime())) return null
    if (!timeZone || /(?:Z|[+-]\d{2}:\d{2})$/i.test(value)) {
      return DateManager.formatDateForAPI(parsed, timeZone)
    }

    const parts = value.match(
      /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2}))?$/,
    )
    if (!parts) return null
    const [, year, month, day, hour, minute, second = "0"] = parts
    const wallTime = Date.UTC(year, month - 1, day, hour, minute, second)
    let instant = wallTime
    let previous = wallTime
    for (let attempt = 0; attempt < 4; attempt++) {
      const zoned = DateManager.formatDateForAPI(new Date(instant), timeZone)
      const offset = zoned.match(/([+-])(\d{2}):(\d{2})$/)
      const minutes =
        (offset[1] === "+" ? 1 : -1) *
        (Number(offset[2]) * 60 + Number(offset[3]))
      const next = wallTime - minutes * 60000
      if (next === instant) return zoned
      previous = instant
      instant = next
    }
    return DateManager.formatDateForAPI(
      new Date(Math.max(instant, previous)),
      timeZone,
    )
  }

  static parseMonthSelector(value, timeZone) {
    const [year, month] = value.split("-")
    const lastDay = new Date(Date.UTC(year, month, 0)).getUTCDate()

    return {
      startDate: DateManager.formatLocalDateForAPI(
        `${year}-${month}-01T00:00:00`,
        timeZone,
      ),
      endDate: DateManager.formatLocalDateForAPI(
        `${year}-${month}-${lastDay}T23:59:00`,
        timeZone,
      ),
    }
  }
}
