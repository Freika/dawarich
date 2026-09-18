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
    const layerManager = this.controller?.layerManager
    if (layerManager?.getLayer("routes")?.data?.features?.length)
      return "routes"
    if (layerManager?.getLayer("tracks")?.data?.features?.length)
      return "tracks"
    return "routes"
  }

  trackGeojson() {
    return (
      this.controller?.layerManager?.getLayer(this.trackSource())?.data ??
      EMPTY_COLLECTION
    )
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

  // The map loads points lazily and the poster never needs the points
  // themselves — but that same load is what builds the routes GeoJSON and
  // fills the routes layer. Under tiled rendering the bulk points and tracks
  // fetches are both skipped, so nothing else fills it and a studio that only
  // draws the track still has to force the load.
  async ensureTrackLoaded() {
    await this.controller?.mapDataManager?.ensurePointsLoaded()
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
