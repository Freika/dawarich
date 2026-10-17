export const SPEEDS = [1, 2, 5, 10]

export function speedFromSlider(value) {
  return SPEEDS[Number.parseInt(value, 10) - 1] || 2
}

export function parseTimestamp(timestamp) {
  if (!timestamp) return 0
  if (typeof timestamp === "string") return new Date(timestamp).getTime()
  if (typeof timestamp === "number")
    return timestamp < 10000000000 ? timestamp * 1000 : timestamp
  return 0
}

export function segmentDurationMs(start, end, speed) {
  const fallback = 500 / speed
  if (!start || !end || end <= start) return fallback
  return Math.min(Math.max((end - start) / (60 * speed), 50), 4000)
}

export function interpolate(from, to, progress) {
  return {
    lon: from.lon + (to.lon - from.lon) * progress,
    lat: from.lat + (to.lat - from.lat) * progress,
  }
}

export function createStepper({ manager, speed: initial = 2 }) {
  let speed = initial
  let points = []
  let index = 0
  let current = null
  let next = null
  let duration = 0
  let last = 0

  const time = (point) => parseTimestamp(point && manager.getTimestamp(point))
  const minuteOf = (point) => manager.minuteOfDay(new Date(time(point)))

  function segment() {
    const a = points[index]
    const b = points[index + 1]
    current = a ? manager.getCoordinates(a) : null
    next = b ? manager.getCoordinates(b) : current
    duration = segmentDurationMs(time(a), time(b), speed)
  }

  function start(minute, now) {
    points = manager.getPointsForDay(manager.getCurrentDay())
    if (points.length === 0) return null
    const found = points.findIndex(
      (point) => time(point) && minuteOf(point) >= minute,
    )
    index = found === -1 ? 0 : found
    segment()
    last = now
    return points[index]
  }

  function frame(now) {
    const elapsed = now - last
    const interval = duration || 500 / speed
    const progress = Math.min(elapsed / interval, 1)
    const coords = current && next ? interpolate(current, next, progress) : null
    if (elapsed < interval) return { coords, point: null, done: false }
    last = now
    index++
    let dayChanged = false
    if (index >= points.length) {
      if (!manager.canGoNext()) return { coords, point: null, done: true }
      manager.nextDay()
      dayChanged = true
      points = manager.getPointsForDay(manager.getCurrentDay())
      index = 0
      if (points.length === 0)
        return { coords, point: null, done: true, dayChanged }
    }
    const point = points[index]
    segment()
    return { coords, point, minute: minuteOf(point), done: false, dayChanged }
  }

  function setSpeed(value, now) {
    const previous = duration
    speed = value
    if (points.length === 0) return
    duration = segmentDurationMs(
      time(points[index]),
      time(points[index + 1]),
      speed,
    )
    if (previous > 0) {
      const progress = Math.min((now - last) / previous, 1)
      last = now - progress * duration
    }
  }

  return {
    start,
    frame,
    setSpeed,
    get speed() {
      return speed
    },
  }
}
