function pad(value) {
  return String(value).padStart(2, "0")
}

function dateTimeParts(date, timeZone) {
  const options = {
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hourCycle: "h23",
    ...(timeZone ? { timeZone } : {}),
  }
  const parts = new Intl.DateTimeFormat("en-CA", options).formatToParts(date)
  const value = (type) => parts.find((part) => part.type === type)?.value

  return {
    year: Number(value("year")),
    month: Number(value("month")),
    day: Number(value("day")),
    hour: Number(value("hour")),
    minute: Number(value("minute")),
    second: Number(value("second")),
  }
}

function parseDateTimeInput(value) {
  const match = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})$/.exec(value || "")
  if (!match) return null

  const parts = {
    year: Number(match[1]),
    month: Number(match[2]),
    day: Number(match[3]),
    hour: Number(match[4]),
    minute: Number(match[5]),
    second: 0,
  }
  const timestamp = Date.UTC(
    parts.year,
    parts.month - 1,
    parts.day,
    parts.hour,
    parts.minute,
  )
  const normalized = new Date(timestamp)
  if (
    normalized.getUTCFullYear() !== parts.year ||
    normalized.getUTCMonth() + 1 !== parts.month ||
    normalized.getUTCDate() !== parts.day ||
    normalized.getUTCHours() !== parts.hour ||
    normalized.getUTCMinutes() !== parts.minute
  ) {
    return null
  }

  return parts
}

function utcValue(parts) {
  return Date.UTC(
    parts.year,
    parts.month - 1,
    parts.day,
    parts.hour,
    parts.minute,
    parts.second,
  )
}

function dateTimeWithOffset(value, timeZone) {
  const expected = parseDateTimeInput(value)
  if (!expected) return null
  if (!timeZone) return value

  const expectedUtc = utcValue(expected)
  let timestamp = expectedUtc
  for (let attempt = 0; attempt < 4; attempt++) {
    const actual = dateTimeParts(new Date(timestamp), timeZone)
    const correction = expectedUtc - utcValue(actual)
    if (correction === 0) break
    timestamp += correction
  }

  const actual = dateTimeParts(new Date(timestamp), timeZone)
  if (utcValue(actual) !== expectedUtc) return null

  // A datetime-local control cannot say which occurrence of a repeated wall
  // time the user means during the autumn DST fold. Picking one silently can
  // move the requested range by an hour, so require an unambiguous time.
  for (const minutes of [-180, -120, -90, -60, -30, 30, 60, 90, 120, 180]) {
    const alternative = dateTimeParts(
      new Date(timestamp + minutes * 60_000),
      timeZone,
    )
    if (utcValue(alternative) === expectedUtc) return null
  }

  const offsetMinutes = Math.round((expectedUtc - timestamp) / 60_000)
  const sign = offsetMinutes >= 0 ? "+" : "-"
  const absolute = Math.abs(offsetMinutes)
  return `${value}${sign}${pad(Math.floor(absolute / 60))}:${pad(absolute % 60)}`
}

export function toLocalDateTimeInput(value, timeZone) {
  const date = value instanceof Date ? value : new Date(value)
  if (Number.isNaN(date.getTime())) return ""

  const parts = dateTimeParts(date, timeZone)
  return `${parts.year}-${pad(parts.month)}-${pad(parts.day)}T${pad(parts.hour)}:${pad(parts.minute)}`
}

export function selectableDateTimeRange(start, end, timeZone) {
  if (!start || !end) return null
  const startWithOffset = dateTimeWithOffset(start, timeZone)
  const endWithOffset = dateTimeWithOffset(end, timeZone)
  if (!startWithOffset || !endWithOffset) return null

  const startTime = new Date(startWithOffset).getTime()
  const endTime = new Date(endWithOffset).getTime()
  if (
    !Number.isFinite(startTime) ||
    !Number.isFinite(endTime) ||
    startTime >= endTime
  ) {
    return null
  }

  return { start: startWithOffset, end: endWithOffset }
}

export function formatDateTimeRange(start, end, locale, timeZone) {
  const format = new Intl.DateTimeFormat(locale || undefined, {
    dateStyle: "medium",
    timeStyle: "short",
    ...(timeZone ? { timeZone } : {}),
  })
  const labels = [start, end]
    .map((value) => (value ? new Date(value) : null))
    .filter((date) => date && !Number.isNaN(date.valueOf()))
    .map((date) => format.format(date))

  return [...new Set(labels)].join(" – ")
}
