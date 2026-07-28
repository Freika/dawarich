/**
 * Groups replay photos by day (in the replay timezone) and answers
 * "which photos should be revealed at this playhead time?".
 *
 * Timestamps are treated as absolute instants: `taken_at` is the photo's UTC
 * instant (capturedAt-preferred), compared directly against the UTC playhead.
 * Day keys are derived in the configured timezone so photos land on the same
 * calendar day as the track points (ReplayManager) and trip-day rows.
 */
export class ReplayPhotoIndex {
  constructor({ photos, timezone, getCoordinates }) {
    this.timezone = timezone || "UTC"
    this.getCoordinates = getCoordinates
    this.photosByDay = {}
    this._build(photos || [])
  }

  allPhotos() {
    return Object.values(this.photosByDay).flat()
  }

  dayPhotos(dayKey) {
    return this.photosByDay[dayKey] || []
  }

  revealedPhotos(dayKey, playheadMs) {
    return this.dayPhotos(dayKey).filter((photo) => photo.tsMs <= playheadMs)
  }

  idsToReveal(dayKey, playheadMs) {
    return this.revealedPhotos(dayKey, playheadMs).map((photo) => photo.id)
  }

  hasPhotos() {
    return Object.keys(this.photosByDay).length > 0
  }

  _build(photos) {
    for (const photo of photos) {
      const tsMs = this._parseMs(photo.taken_at)
      if (tsMs === null) continue

      const coords = this.getCoordinates ? this.getCoordinates(photo) : null
      if (!coords) continue

      const dayKey = this._dayKey(tsMs)
      if (!dayKey) continue

      const entry = { ...photo, tsMs, lon: coords.lon, lat: coords.lat }
      if (!this.photosByDay[dayKey]) this.photosByDay[dayKey] = []
      this.photosByDay[dayKey].push(entry)
    }

    for (const key of Object.keys(this.photosByDay)) {
      this.photosByDay[key].sort((a, b) => a.tsMs - b.tsMs)
    }
  }

  _parseMs(takenAt) {
    if (!takenAt) return null
    if (typeof takenAt === "number") {
      return takenAt < 10000000000 ? takenAt * 1000 : takenAt
    }
    const ms = new Date(takenAt).getTime()
    return Number.isNaN(ms) ? null : ms
  }

  _dayKey(tsMs) {
    try {
      return new Intl.DateTimeFormat("en-CA", {
        timeZone: this.timezone,
        year: "numeric",
        month: "2-digit",
        day: "2-digit",
      }).format(new Date(tsMs))
    } catch (_err) {
      return new Date(tsMs).toISOString().slice(0, 10)
    }
  }
}
