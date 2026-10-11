export class PublicDayClock {
  constructor(zone, locale) {
    this.zone = zone
    this.locale = locale
    this.bounds = new Map()
    this.labels = new Map()
    this.formats = {
      parts: new Intl.DateTimeFormat("en-CA", {
        timeZone: zone,
        year: "numeric",
        month: "2-digit",
        day: "2-digit",
        hour: "2-digit",
        minute: "2-digit",
        hourCycle: "h23",
      }),
      zone: new Intl.DateTimeFormat(locale, {
        timeZone: zone,
        timeZoneName: "short",
      }),
      day: new Intl.DateTimeFormat(locale, {
        timeZone: zone,
        dateStyle: "medium",
      }),
    }
  }
  parts(instant) {
    return Object.fromEntries(
      this.formats.parts
        .formatToParts(new Date(instant))
        .map(({ type, value }) => [type, value]),
    )
  }
  key(parts) {
    return `${parts.year}-${parts.month}-${parts.day}`
  }
  midnight(year, month, day) {
    const target = Date.UTC(year, month - 1, day)
    let instant = target
    for (let attempt = 0; attempt < 3; attempt++) {
      const parts = this.parts(instant)
      const actual = Date.UTC(
        Number(parts.year),
        Number(parts.month) - 1,
        Number(parts.day),
        Number(parts.hour),
        Number(parts.minute),
      )
      const delta = target - actual
      if (delta === 0) break
      instant += delta
    }
    return instant
  }
  day(key) {
    if (!this.bounds.has(key)) {
      const [year, month, day] = key.split("-").map(Number)
      const start = this.midnight(year, month, day)
      const next = new Date(Date.UTC(year, month - 1, day + 1))
      const end = this.midnight(
        next.getUTCFullYear(),
        next.getUTCMonth() + 1,
        next.getUTCDate(),
      )
      this.bounds.set(key, { start, length: Math.round((end - start) / 60000) })
    }
    return this.bounds.get(key)
  }
  minute(point) {
    const instant = point[2] * 1000
    return Math.floor(
      (instant - this.day(this.key(this.parts(instant))).start) / 60000,
    )
  }
  label(point) {
    const instant = point[2] * 1000
    const minute = Math.floor(instant / 60000)
    if (this.labels.has(minute)) return this.labels.get(minute)
    const parts = this.parts(instant)
    const time = `${parts.hour}:${parts.minute}`
    const repeated = [-3600000, 3600000].some((offset) => {
      const adjacent = this.parts(instant + offset)
      return (
        this.key(parts) === this.key(adjacent) &&
        parts.hour === adjacent.hour &&
        parts.minute === adjacent.minute
      )
    })
    if (!repeated) {
      this.labels.set(minute, time)
      return time
    }
    const zone = this.formats.zone
      .formatToParts(new Date(instant))
      .find(({ type }) => type === "timeZoneName").value
    const label = `${time} ${zone}`
    this.labels.set(minute, label)
    return label
  }
  clear() {
    this.bounds.clear()
    this.labels.clear()
    this.formats = null
  }
}
