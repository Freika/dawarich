const EMPTY_COLLECTION = { type: "FeatureCollection", features: [] }

export class MapPageProvider {
  constructor({ application }) {
    this.application = application
    this.supportsDateNavigation = true
  }

  get controller() {
    const container = document.getElementById("maps-maplibre-container")
    return (
      container &&
      this.application.getControllerForElementAndIdentifier(
        container,
        "maps--maplibre",
      )
    )
  }

  trackSource() {
    return "tracks"
  }

  trackGeojson() {
    return this._tracks ?? EMPTY_COLLECTION
  }

  dateRange() {
    return {
      startAt: this.controller?.startDateValue || "",
      endAt: this.controller?.endDateValue || "",
    }
  }

  timeZone() {
    return this.controller?.timezoneValue || undefined
  }

  // Poster/video generation is an explicit bounded consumer, so it may fetch
  // exact Points and canonical Tracks without making the browsing map bulk-load.
  async ensureTrackLoaded() {
    const controller = this.controller
    if (!controller) return
    const { startAt, endAt } = this.dateRange()
    const [, tracks] = await Promise.all([
      controller.mapDataManager?.ensurePointsLoaded(),
      controller.api.fetchTracks({ start_at: startAt, end_at: endAt }),
    ])
    this._tracks = tracks || EMPTY_COLLECTION
  }

  // Timestamped points, for consumers that animate the track rather than
  // draw it flat.
  async points() {
    const controller = this.controller
    if (!controller) return []
    await this.ensureTrackLoaded()
    return controller._getLoadedPoints?.() ?? []
  }

  fallbackBounds() {
    const bounds = this.controller?.map?.getBounds()
    if (!bounds) return null
    return [
      [bounds.getWest(), bounds.getSouth()],
      [bounds.getEast(), bounds.getNorth()],
    ]
  }

  defaultTitle() {
    return ""
  }

  async applyDates(start, end) {
    const params = new URLSearchParams(window.location.search)
    params.set("start_at", start)
    params.set("end_at", end)
    window.history.pushState({}, "", `/map/v2?${params.toString()}`)
    const pending = []
    document.dispatchEvent(
      new CustomEvent("timeline-feed:date-navigated", {
        detail: {
          startAt: start,
          endAt: end,
          waitUntil: (promise) => pending.push(Promise.resolve(promise)),
        },
      }),
    )
    if (!pending.length) throw new Error("Map date navigation is unavailable")
    await Promise.all(pending)
  }
}

export function buildTripGeojson({
  dayRouteCollections = [],
  pathData = null,
}) {
  const features = []
  for (const collection of dayRouteCollections) {
    features.push(...(collection?.features ?? []))
  }
  if (!features.length && pathData) {
    try {
      const coordinates = JSON.parse(pathData)
      if (Array.isArray(coordinates) && coordinates.length >= 2) {
        features.push({
          type: "Feature",
          properties: {},
          geometry: { type: "LineString", coordinates },
        })
      }
    } catch {
      // malformed path data falls through to an empty collection
    }
  }
  return { type: "FeatureCollection", features }
}

export class TripProvider {
  constructor({
    geojson,
    posterGeojson,
    startAt,
    endAt,
    title,
    points,
    timezone,
  }) {
    this.geojson = geojson ?? EMPTY_COLLECTION
    this.posterGeometry = posterGeojson ?? this.geojson
    this.startAt = startAt
    this.endAt = endAt
    this.title = title ?? ""
    this.trackPoints = points ?? []
    this.timezone = timezone
    this.supportsDateNavigation = false
  }

  trackSource() {
    return "routes"
  }

  trackGeojson() {
    return this.geojson
  }

  // Posters can include visible flight arcs; video still animates GPS points.
  posterGeojson() {
    return this.posterGeometry
  }

  dateRange() {
    return { startAt: this.startAt, endAt: this.endAt }
  }

  timeZone() {
    return this.timezone || undefined
  }

  fallbackBounds() {
    return null
  }

  defaultTitle() {
    return this.title
  }

  // Nothing to load: a trip hands the studio its geojson up front.
  async ensureTrackLoaded() {}

  async points() {
    return this.trackPoints
  }
}
