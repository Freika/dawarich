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

  // SPA date change, same as the timeline: dispatch the shared event so the
  // main map reloads its layers in place. The URL is pushed for
  // browser-state consistency.
  async applyDates(start, end) {
    const params = new URLSearchParams(window.location.search)
    params.set("start_at", start)
    params.set("end_at", end)
    window.history.pushState({}, "", `/map/v2?${params.toString()}`)
    document.dispatchEvent(
      new CustomEvent("timeline-feed:date-navigated", {
        detail: { startAt: start, endAt: end },
      }),
    )
    await this.waitForTrackReload()
  }

  // The reload replaces the layer data objects; wait for the identity to
  // change and then stay stable for two polls (progressive loading lands
  // in several passes), capped at ~16s.
  async waitForTrackReload() {
    const layerManager = this.controller?.layerManager
    const snapshot = () => ({
      routes: layerManager?.getLayer("routes")?.data,
      tracks: layerManager?.getLayer("tracks")?.data,
    })
    const before = snapshot()
    let changed = false
    let stable = 0
    let last = before
    for (let i = 0; i < 40; i++) {
      await new Promise((resolve) => setTimeout(resolve, 400))
      const current = snapshot()
      if (current.routes !== before.routes || current.tracks !== before.tracks)
        changed = true
      if (changed) {
        stable =
          current.routes === last.routes && current.tracks === last.tracks
            ? stable + 1
            : 0
        if (stable >= 2) return
      }
      last = current
    }
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
  constructor({ geojson, startAt, endAt, title }) {
    this.geojson = geojson ?? EMPTY_COLLECTION
    this.startAt = startAt
    this.endAt = endAt
    this.title = title ?? ""
    this.supportsDateNavigation = false
  }

  trackSource() {
    return "routes"
  }

  trackGeojson() {
    return this.geojson
  }

  dateRange() {
    return { startAt: this.startAt, endAt: this.endAt }
  }

  fallbackBounds() {
    return null
  }

  defaultTitle() {
    return this.title
  }
}
