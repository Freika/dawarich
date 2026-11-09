import { translate } from "i18n"
import * as maplibregl from "maplibre-gl"
import { Toast } from "maps_maplibre/components/toast"

export function parseSegments(properties) {
  try {
    return typeof properties.segments === "string"
      ? JSON.parse(properties.segments)
      : properties.segments || []
  } catch (err) {
    console.warn("Failed to parse track segments:", err)
    return []
  }
}

export function createEmojiMarker(emoji, markerClass = "route-emoji-marker") {
  const el = document.createElement("div")
  el.className = markerClass
  el.textContent = emoji
  el.style.fontSize = "24px"
  el.style.cursor = "pointer"
  el.style.userSelect = "none"

  return new maplibregl.Marker({ element: el, anchor: "center" })
}

/**
 * The track the user clicked: its feature, the lazily fetched segments and
 * their emoji markers. A generation token drops responses for an older click.
 */
export class TrackSelection {
  constructor(map, controller) {
    this.map = map
    this.controller = controller
    this.feature = null
    this.generation = 0
    this.markers = []
  }

  get tracksLayer() {
    return this.controller.layerManager?.getLayer("tracks")
  }

  /** Highlight a clicked track and start loading its segments. */
  select(feature) {
    const generation = ++this.generation
    this.feature = feature
    try {
      this.tracksLayer?.setSelectedTrack(feature)
    } catch (err) {
      console.warn("[TrackSelection] Failed to highlight track:", err)
    }
    return this.loadSegments(feature.properties.id, feature, generation)
  }

  async loadSegments(trackId, clicked, generation = this.generation) {
    try {
      const trackFeature = await this.controller.api.fetchTrackWithSegments(
        trackId,
        { ...this.controller.layerManager?.pointTileRange },
      )
      if (generation !== this.generation || this.feature !== clicked) return
      if (!trackFeature) return

      // The clicked MVT feature is clipped to a tile; segment visualization
      // must use the canonical linestring returned by the focused fetch.
      const displayFeature = trackFeature.geometry ? trackFeature : clicked
      if (displayFeature !== clicked) {
        this.feature = displayFeature
        this.tracksLayer?.setSelectedTrack(displayFeature)
      }

      const segments = parseSegments(trackFeature.properties)
      const tracksLayer = this.tracksLayer
      if (tracksLayer) {
        tracksLayer.showSegments(displayFeature, segments)
        tracksLayer.setSegmentHoverCallback((segmentIndex) => {
          this._highlightSegment(segmentIndex)
          this._dispatchSegmentHover(trackId, segments[segmentIndex]?.id)
        })
        tracksLayer.setSegmentLeaveCallback(() => {
          this._clearSegmentHighlight()
          this._dispatchSegmentUnhover(trackId)
        })
      }

      this._createMarkers(trackId, displayFeature, segments)
    } catch (error) {
      if (generation !== this.generation) return
      console.error("Failed to load track segments:", error)
      Toast.error(translate("messages.failed_to_load_track_details"))
    }
  }

  /** Drop the selection and its map decorations. Returns false if none. */
  clear() {
    if (!this.feature) return false

    this.reset()
    const tracksLayer = this.tracksLayer
    if (tracksLayer) {
      tracksLayer.setSelectedTrack(null)
      tracksLayer.hideSegments()
      tracksLayer.setSegmentHoverCallback(null)
      tracksLayer.setSegmentLeaveCallback(null)
    }
    return true
  }

  /** Forget the selection without touching the tracks layer. */
  reset() {
    this.generation += 1
    this.feature = null
    this.clearMarkers()
  }

  /** Reload segments after one changed mode, so colours and emoji follow. */
  refreshSegments(trackId) {
    const feature = this.feature
    if (!feature || String(feature.properties?.id) !== String(trackId)) return
    return this.loadSegments(feature.properties.id, feature)
  }

  clearMarkers() {
    for (const marker of this.markers) marker.remove()
    this.markers = []
  }

  _createMarkers(trackId, feature, segments) {
    this.clearMarkers()

    if (feature?.geometry?.type !== "LineString") return
    if (!segments || segments.length === 0) return

    const coords = feature.geometry.coordinates
    if (coords.length < 2) return

    for (const segment of segments) {
      const coord =
        coords[Math.min(segment.start_index || 0, coords.length - 1)]
      if (!coord) continue

      const marker = createEmojiMarker(
        segment.emoji || "❓",
        "track-emoji-marker",
      )
      marker.trackId = trackId
      marker.segmentId = segment.id
      marker.setLngLat(coord).addTo(this.map)
      this.markers.push(marker)
    }

    const endMarker = createEmojiMarker("🏁", "track-emoji-marker")
    endMarker.setLngLat(coords[coords.length - 1]).addTo(this.map)
    this.markers.push(endMarker)
  }

  _highlightSegment(segmentIndex) {
    const layerId = this.tracksLayer?.segmentLayerId
    if (!layerId || !this.map.getLayer(layerId)) return

    const hovered = ["==", ["get", "segmentIndex"], segmentIndex]
    this.map.setPaintProperty(layerId, "line-opacity", [
      "case",
      hovered,
      1.0,
      0.4,
    ])
    this.map.setPaintProperty(layerId, "line-width", ["case", hovered, 8, 4])
  }

  _clearSegmentHighlight() {
    const layerId = this.tracksLayer?.segmentLayerId
    if (!layerId || !this.map.getLayer(layerId)) return

    this.map.setPaintProperty(layerId, "line-opacity", 0.9)
    this.map.setPaintProperty(layerId, "line-width", 6)
  }

  _dispatchSegmentHover(trackId, segmentId) {
    if (!segmentId) return
    document.dispatchEvent(
      new CustomEvent("dawarich:segment-hover", {
        detail: { trackId, segmentId },
      }),
    )
  }

  _dispatchSegmentUnhover(trackId) {
    document.dispatchEvent(
      new CustomEvent("dawarich:segment-unhover", { detail: { trackId } }),
    )
  }
}
