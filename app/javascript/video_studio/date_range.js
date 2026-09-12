function pad(value) {
  return String(value).padStart(2, "0")
}

// datetime-local expects wall-clock fields without a timezone suffix. Converting
// through the local Date getters keeps the time shown in the picker aligned
// with the map controller's local range.
export function toLocalDateTimeInput(value) {
  const date = value instanceof Date ? value : new Date(value)
  if (Number.isNaN(date.getTime())) return ""

  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`
}

export function selectableDateTimeRange(start, end) {
  if (!start || !end) return null
  const startTime = new Date(start).getTime()
  const endTime = new Date(end).getTime()
  if (
    !Number.isFinite(startTime) ||
    !Number.isFinite(endTime) ||
    startTime >= endTime
  ) {
    return null
  }

  return { start, end }
}

export function formatDateTimeRange(start, end, locale) {
  const format = new Intl.DateTimeFormat(locale || undefined, {
    dateStyle: "medium",
    timeStyle: "short",
  })
  const labels = [start, end]
    .map((value) => (value ? new Date(value) : null))
    .filter((date) => date && !Number.isNaN(date.valueOf()))
    .map((date) => format.format(date))

  return [...new Set(labels)].join(" – ")
}
