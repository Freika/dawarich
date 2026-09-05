import { CleanupHelper } from "../utils/cleanup_helper"

// Temporary use of the existing track shimmer. A newer selection always wins;
// hover must never restore an old track over a click or a date change.
export class TimelineSegmentHover {
  constructor(controller, isEnabled) {
    this.controller = controller
    this.isEnabled = isEnabled
    this.cleanup = new CleanupHelper()
    this.generation = 0
    this.cleanup.addEventListener(
      document,
      "dawarich:segment-hover",
      (event) => {
        if (event.target === document) return // map-to-row notification
        this.hover(event)
      },
    )
    this.cleanup.addEventListener(
      document,
      "dawarich:segment-unhover",
      (event) => {
        if (event.target === this.row) this.leave()
      },
    )
    for (const event of [
      "timeline-feed:entry-hover",
      "timeline-feed:entry-click",
      "timeline-feed:entry-deselect",
      "timeline-feed:date-navigated",
      "timeline-feed:day-collapsed",
      "dawarich:segment-mode-changed",
    ]) {
      this.cleanup.addEventListener(document, event, () => this.reset())
    }
    this.onMapClick = () => this.reset()
    controller.map.on("click", this.onMapClick)
    controller.map.on("style.load", this.onMapClick)
  }

  get layer() {
    return this.controller.layerManager.getLayer("tracks")
  }

  async hover(event) {
    this.leave()
    const { trackId, segmentId } = event.detail
    if (!trackId || !segmentId || !this.isEnabled() || !this.layer) return
    const layer = this.layer
    const source = this.controller.map.getSource(layer.selectionSourceId)
    if (!source) return
    const revision = layer.selectionRevision
    const generation = this.generation
    this.row = event.target
    try {
      const track = await this.loadTrack(trackId)
      if (
        generation !== this.generation ||
        !this.row?.isConnected ||
        !this.isEnabled() ||
        layer !== this.layer ||
        this.controller.map.getSource(layer.selectionSourceId) !== source ||
        layer.selectionRevision !== revision
      )
        return
      const segment = track?.properties?.segments?.find(
        (item) => String(item.id) === String(segmentId),
      )
      const coordinates = segmentCoordinates(track, segment)
      if (!coordinates) return

      this.previous = {
        layer,
        source,
        feature: layer.selectedFeature,
        opacity: this.controller.map.getLayer(layer.id)
          ? this.controller.map.getPaintProperty(layer.id, "line-opacity")
          : null,
      }
      layer.setSelectedTrack(
        {
          type: "Feature",
          geometry: { type: "LineString", coordinates },
          properties: {
            ...track.properties,
            color: segment.color || track.properties.color,
          },
        },
        { preserveSegments: true },
      )
      this.ownedRevision = layer.selectionRevision
    } catch {
      // Hover is optional: retain the ordinary track highlight on failure.
      // Failed requests are evicted by loadTrack so another hover can retry.
    }
  }

  loadTrack(trackId) {
    if (this.cached?.id === String(trackId)) return this.cached.promise
    this.cached?.abort.abort()
    const abort = new AbortController()
    const entry = { id: String(trackId), abort }
    entry.promise = this.controller.api
      .fetchTrackWithSegments(trackId, { signal: abort.signal })
      .catch((error) => {
        if (this.cached === entry) this.cached = null
        throw error
      })
    this.cached = entry
    return entry.promise
  }

  leave() {
    this.generation += 1
    this.row = null
    const layer = this.layer
    if (
      this.previous &&
      layer === this.previous.layer &&
      this.controller.map.getSource(layer.selectionSourceId) ===
        this.previous.source &&
      layer.selectionRevision === this.ownedRevision
    ) {
      layer.setSelectedTrack(this.previous.feature, { preserveSegments: true })
      if (
        this.previous.opacity != null &&
        this.controller.map.getLayer(layer.id)
      ) {
        this.controller.map.setPaintProperty(
          layer.id,
          "line-opacity",
          this.previous.opacity,
        )
      }
    }
    this.previous = null
    this.ownedRevision = null
  }

  reset() {
    this.leave()
    this.cached?.abort.abort()
    this.cached = null
  }

  destroy() {
    this.reset()
    this.cleanup.cleanup()
    this.controller.map.off("click", this.onMapClick)
    this.controller.map.off("style.load", this.onMapClick)
  }
}

export function segmentCoordinates(track, segment) {
  if (!segment) return null
  let coordinates = segment.coordinates
  if (!coordinates) {
    const { start_index: start, end_index: end } = segment
    const full = track?.geometry?.coordinates
    if (
      track?.geometry?.type !== "LineString" ||
      !Array.isArray(full) ||
      !Number.isInteger(start) ||
      !Number.isInteger(end) ||
      start < 0 ||
      end < start ||
      end >= full.length
    )
      return null
    coordinates = full.slice(start, end + 1)
  }
  return Array.isArray(coordinates) &&
    coordinates.length >= 2 &&
    coordinates.every(
      (point) =>
        Array.isArray(point) &&
        point.length >= 2 &&
        Number.isFinite(point[0]) &&
        Number.isFinite(point[1]),
    )
    ? coordinates
    : null
}
