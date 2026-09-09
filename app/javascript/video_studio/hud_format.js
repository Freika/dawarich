// Text formatting for the replay HUD, matching the Replay Frames design:
// "14 JUN 2026 · 08:41", "08 — 26 JUN 2026", "5d 14h", "DAY 06 / 18".
// Timestamps are formatted in the viewer's local timezone.
const KM_PER_MILE = 1.609344
const MONTHS = [
  "JAN",
  "FEB",
  "MAR",
  "APR",
  "MAY",
  "JUN",
  "JUL",
  "AUG",
  "SEP",
  "OCT",
  "NOV",
  "DEC",
]
const DAY_MS = 24 * 3600 * 1000

const pad = (n) => String(n).padStart(2, "0")

export function splitDistance(meters, units = "km") {
  if (!Number.isFinite(meters))
    return { value: "0", unit: units === "mi" ? "mi" : "m" }
  if (units === "mi")
    return { value: (meters / 1000 / KM_PER_MILE).toFixed(1), unit: "mi" }
  if (meters < 1000) return { value: String(Math.round(meters)), unit: "m" }
  return { value: (meters / 1000).toFixed(1), unit: "km" }
}

export function formatClockDate(ts) {
  const d = new Date(ts)
  return `${pad(d.getDate())} ${MONTHS[d.getMonth()]} ${d.getFullYear()} · ${pad(d.getHours())}:${pad(d.getMinutes())}`
}

export function formatShortDate(ts) {
  const d = new Date(ts)
  return `${pad(d.getDate())} ${MONTHS[d.getMonth()]}`
}

export function formatDateRange(startTs, endTs) {
  const a = new Date(startTs)
  const b = new Date(endTs)
  const sameDay =
    a.getFullYear() === b.getFullYear() &&
    a.getMonth() === b.getMonth() &&
    a.getDate() === b.getDate()
  if (sameDay)
    return `${pad(a.getDate())} ${MONTHS[a.getMonth()]} ${a.getFullYear()}`
  if (a.getFullYear() === b.getFullYear()) {
    if (a.getMonth() === b.getMonth()) {
      return `${pad(a.getDate())} — ${pad(b.getDate())} ${MONTHS[b.getMonth()]} ${b.getFullYear()}`
    }
    return `${pad(a.getDate())} ${MONTHS[a.getMonth()]} — ${pad(b.getDate())} ${MONTHS[b.getMonth()]} ${b.getFullYear()}`
  }
  return `${pad(a.getDate())} ${MONTHS[a.getMonth()]} ${a.getFullYear()} — ${pad(b.getDate())} ${MONTHS[b.getMonth()]} ${b.getFullYear()}`
}

function calendarDay(ts) {
  const d = new Date(ts)
  return new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime()
}

export function dayNumber(startTs, ts) {
  return Math.max(
    1,
    Math.round((calendarDay(ts) - calendarDay(startTs)) / DAY_MS),
  )
}

export function dayTotal(startTs, endTs) {
  return Math.max(
    1,
    Math.round((calendarDay(endTs) - calendarDay(startTs)) / DAY_MS),
  )
}
