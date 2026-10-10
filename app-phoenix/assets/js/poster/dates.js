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

export function toLocalDateTimeInput(value, timeZone) {
  const date = value instanceof Date ? value : new Date(value)
  if (Number.isNaN(date.getTime())) return ""

  const parts = dateTimeParts(date, timeZone)
  return `${parts.year}-${pad(parts.month)}-${pad(parts.day)}T${pad(parts.hour)}:${pad(parts.minute)}`
}

export function dateRangeLabel(range, timeZone) {
  const { startAt, endAt } = range ?? {}
  if (!startAt || !endAt) return ""
  const options = { day: "numeric", month: "short", year: "numeric", timeZone }
  const start = new Date(startAt).toLocaleDateString("en-GB", options)
  const end = new Date(endAt).toLocaleDateString("en-GB", options)
  return `${start} – ${end}`
}

export function presetRange(kind, now, timeZone) {
  const nowLocal = toLocalDateTimeInput(now, timeZone)
  const start = new Date(`${nowLocal}:00Z`)
  if (kind === "today") start.setUTCHours(0, 0, 0, 0)
  else if (kind === "week") start.setUTCDate(start.getUTCDate() - 7)
  else if (kind === "month") start.setUTCMonth(start.getUTCMonth() - 1)
  return { start: start.toISOString().slice(0, 16), end: nowLocal }
}
