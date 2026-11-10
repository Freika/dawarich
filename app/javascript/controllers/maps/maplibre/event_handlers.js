import { translate } from "i18n"
import * as maplibregl from "maplibre-gl"
import { Toast } from "maps_maplibre/components/toast"
import { PointDragGesture } from "maps_maplibre/editing/point_drag_gesture"
import { formatSpeed } from "maps_maplibre/utils/format_helpers"
import {
  escapeHtml,
  formatTimestamp,
} from "maps_maplibre/utils/geojson_transformers"
import { isGatedPlan } from "maps_maplibre/utils/layer_gate"
import { SettingsManager } from "maps_maplibre/utils/settings_manager"

/**
 * Format the coordinates a feature carries in its properties. Returns null when
 * either is absent or blank, so the caller can fall back to the geometry.
 * `Number("")` is 0 and finite, so a plain isFinite check is not enough.
 */
export function shouldShowPointPopup(properties = {}) {
  if (properties.id == null) return false
  return (properties.count ?? 1) <= 1
}

function storedCoordinates(properties) {
  const { latitude, longitude } = properties
  if (latitude == null || longitude == null) return null
  if (latitude === "" || longitude === "") return null

  const lat = Number(latitude)
  const lon = Number(longitude)
  if (!Number.isFinite(lat) || !Number.isFinite(lon)) return null

  return `${lat.toFixed(6)}, ${lon.toFixed(6)}`
}

export class EventHandlers {
  constructor(map, controller) {
    this.map = map
    this.controller = controller
    this.trackSelection = new TrackSelection(map, controller)

    // Bound handler for track point clicks — stored so the same reference can be
    // used for both map.on() and map.off() during toggle cleanup
    this._handleTrackPointClick = this.handleTrackPointClick.bind(this)

    this.pointDrag = new PointDragGesture(map, {
      isEnabled: () => this._pointEditingEnabled(),
      getEditor: () => this._mapEditor(),
      isSinglePoint: shouldShowPointPopup,
    })
    this.pointDrag.attach()

    this._boundOnSegmentModeChanged = this._onSegmentModeChanged.bind(this)
    document.addEventListener(
      "dawarich:segment-mode-changed",
      this._boundOnSegmentModeChanged,
    )
  }

  /**
   * Tear down document-level listeners and DOM markers. Must be called from
   * the parent Stimulus controller's `disconnect()` so Turbo navigations
   * don't accumulate stale `dawarich:segment-mode-changed` listeners.
   */
  destroy() {
    this.pointDrag?.detach()
    if (this._boundOnSegmentModeChanged) {
      document.removeEventListener(
        "dawarich:segment-mode-changed",
        this._boundOnSegmentModeChanged,
      )
      this._boundOnSegmentModeChanged = null
    }
    this.teardownLayerInteractions()
  }

  get selectedTrackFeature() {
    return this.trackSelection.feature
  }

  set selectedTrackFeature(feature) {
    this.trackSelection.feature = feature
  }

  teardownLayerInteractions() {
    this.pointDrag?.cancel()
    this.map.off("click", "track-points", this._handleTrackPointClick)
    this.trackSelection.reset()
  }

  /** Handle a tile Point; address details load through the existing info UI. */
  handlePointClick(e) {
    // Check if the click is a follow-on event from a drag operation
    const mapEditor = this.controller.layerManager.getLayer("map-editor")
    if (mapEditor?.justDragged) return

    const feature = e.features?.[0]
    if (!feature) return
    this.clearTrackSelection()
    if (!shouldShowPointPopup(feature.properties)) {
      if (feature.layer?.id === "points-mvt") {
        const zoom = this.map.getZoom()
        const nextZoom = Math.min(zoom + 2, this.map.getMaxZoom?.() ?? 22)
        if (nextZoom > zoom) {
          this.map.easeTo({ center: e.lngLat, zoom: nextZoom, duration: 350 })
        } else {
          this.controller.showInfo(
            translate("map_info.location_point"),
            `<p>${translate("map_info.overlapping_points", {
              count: Number(feature.properties.count) || 2,
            })}</p>`,
          )
        }
      }
      return
    }
    this._showPointFeature(feature)
  }

  _showPointFeature(feature) {
    if (feature.layer?.id === "points-mvt" && this._pointEditingEnabled()) {
      this._openPointEditor(feature).catch((error) => {
        console.error("[EventHandlers] Failed to open point editor:", error)
        Toast.error(translate("messages.failed_to_load_track_points"))
      })
    }

    const pointId = feature.properties.id
    const actions = pointId
      ? [
          {
            type: "button",
            handler: "handleDelete",
            id: pointId,
            entityType: "point",
            label: translate("messages.delete"),
          },
        ]
      : []

    this.controller.showInfo(
      translate("map_info.location_point"),
      this._buildPointInfoContent(feature.properties, feature.geometry),
      actions,
    )
  }

  /**
   * Handle anomaly point click — shows reason and timestamp in the info panel.
   */
  handleAnomalyClick(e) {
    const feature = e.features[0]
    const anomaliesLayer = this.controller.layerManager.getLayer("anomalies")
    if (!anomaliesLayer) return

    const content = anomaliesLayer.buildPopupContent(feature.properties)
    const pointId = feature.properties.id
    const actions = pointId
      ? [
          {
            type: "button",
            handler: "markPointValid",
            id: pointId,
            entityType: "point",
            label: translate("messages.mark_point_valid"),
          },
        ]
      : []
    this.controller.showInfo(
      translate("messages.anomaly_point"),
      content,
      actions,
    )
  }

  handleEditablePointClick(e) {
    const mapEditor = this.controller.layerManager.getLayer("map-editor")
    if (!mapEditor?.forEditing || mapEditor.justDragged) return
    if (
      this.map.getLayer("points-mvt") &&
      this.map.queryRenderedFeatures(e.point, { layers: ["points-mvt"] })
        .length > 0
    )
      return

    const feature = e.features?.[0]
    if (feature) this._showPointFeature(feature)
  }

  /**
   * Handle track point click — injects point info into the existing track info panel.
   * Suppresses the event if the user just finished dragging (justDragged flag).
   */
  handleTrackPointClick(e) {
    // Check if the click is a follow-on event from a drag operation
    const mapEditor = this.controller.layerManager.getLayer("map-editor")
    if (mapEditor?.justDragged) return

    const container = document.getElementById(
      `track-point-info-container-${mapEditor?.trackId}`,
    )
    if (!container) return

    const feature = e.features[0]
    container.innerHTML = `
      <div class="mt-3 pt-3 border-t border-base-300">
        <div class="text-sm font-semibold mb-1">${translate("map_info.selected_point")}</div>
        ${this._buildPointInfoContent(feature.properties, feature.geometry)}
      </div>
    `
  }

  /**
   * Build HTML content for point info display (shared by regular and track points)
   * Address is loaded asynchronously via a Turbo Frame.
   * @param {Object} properties - GeoJSON feature properties
   * @param {Object} geometry - GeoJSON geometry with coordinates
   * @returns {string} HTML content string
   * @private
   */
  _buildPointInfoContent(properties, geometry) {
    const distanceUnit = this.controller.settings.distance_unit || "km"
    // Prefer the stored values carried in the properties. A clicked feature's
    // geometry comes back snapped to the tile grid, so reading coordinates off
    // it shows a position that doesn't match the one in the points list.
    const stored = storedCoordinates(properties)
    const coords = geometry?.coordinates
    const coordStr =
      stored ??
      (coords && coords.length >= 2
        ? `${coords[1].toFixed(6)}, ${coords[0].toFixed(6)}`
        : null)
    const pointId = properties.id
    const addressFrame = pointId
      ? `<turbo-frame id="point-address-${pointId}" src="/points/${pointId}/address" loading="lazy"></turbo-frame>`
      : ""
    return `
      <div class="space-y-2">
        ${addressFrame}
        ${coordStr ? `<div><span class="font-semibold">${translate("map_info.coordinates")}:</span> ${coordStr}</div>` : ""}
        <div><span class="font-semibold">${translate("map_info.time")}:</span> ${formatTimestamp(properties.timestamp, this.controller.timezoneValue)}</div>
        ${properties.battery ? `<div><span class="font-semibold">${translate("map_info.battery")}:</span> ${properties.battery}%</div>` : ""}
        ${properties.altitude ? `<div><span class="font-semibold">${translate("map_info.altitude")}:</span> ${Math.round(properties.altitude)}m</div>` : ""}
        ${properties.velocity ? `<div><span class="font-semibold">${translate("map_info.speed")}:</span> ${formatSpeed(properties.velocity * 3.6, distanceUnit)}</div>` : ""}
      </div>
    `
  }

  /**
   * Handle visit click — opens the Timeline tab, selects the visit's day, and
   * queues the visit for halo highlighting. Replaces the old Tools-tab flow
   * (info panel + Edit button) which is gone with the unified timeline.
   */
  handleVisitClick(e) {
    const properties = e.features[0].properties
    const visitId = Number(properties.id)
    const startedAt =
      typeof properties.started_at === "string" ? properties.started_at : null
    const date = startedAt ? startedAt.slice(0, 10) : null

    document.dispatchEvent(
      new CustomEvent("timeline:open-visit", {
        detail: { visitId, date },
      }),
    )
  }

  handlePhotoClick(e) {
    const feature = e.features[0]
    const properties = feature.properties

    const content = `
      <div class="space-y-2">
        ${properties.photo_url ? `<img src="${escapeHtml(properties.photo_url)}" alt="${translate("map_info.photo")}" class="w-full rounded-lg mb-2" />` : ""}
        ${properties.taken_at ? `<div><span class="font-semibold">${translate("map_info.taken")}:</span> ${formatTimestamp(properties.taken_at, this.controller.timezoneValue)}</div>` : ""}
      </div>
    `

    this.controller.showInfo(translate("map_info.photo"), content)
  }

  handlePlaceClick(e) {
    this.controller.placePanel.open(e.features[0].properties.id)
  }

  /**
   * Handle track click — opens the Timeline tab, navigates to the track's day,
   * and expands the matching journey entry so the track's full details
   * (distance, speed, elevation, replay, show-points toggle) are shown inline.
   * Replaces the old Tools-tab flow.
   */
  handleTrackClick(e) {
    // MapLibre dispatches a click to every intersected layer. A point drawn
    // above a track must keep its selection instead of opening the track.
    if (this.map.getLayer("points-mvt")) {
      const pointFeatures = this.map.queryRenderedFeatures(e.point, {
        layers: ["points-mvt"],
      })
      if (pointFeatures.length > 0) return
    }

    // Track points are part of a selected track and take the same priority.
    if (this.map.getLayer("track-points")) {
      const trackPointFeatures = this.map.queryRenderedFeatures(e.point, {
        layers: ["track-points"],
      })
      if (trackPointFeatures.length > 0) return
    }

    const clickedFeature = e.features[0]
    if (!clickedFeature) return

    const properties = clickedFeature.properties
    // The on-map highlight and segments are feedback for the click itself,
    // independent of the info surface.
    void this.trackSelection.select(clickedFeature)

    // Derive the day from the track's start. `start_at` comes from our own
    // serializer as an ISO8601 string — safe to slice the date portion.
    const startAt =
      typeof properties.start_at === "string" ? properties.start_at : null
    const date = startAt ? startAt.slice(0, 10) : null
    const trackId = Number(properties.id)

    document.dispatchEvent(
      new CustomEvent("timeline:open-track", {
        detail: { trackId, date, startAt },
      }),
    )
  }

  _onSegmentModeChanged(event) {
    this.trackSelection.refreshSegments(event.detail.trackId)
  }

  clearTrackSelection({ preserveEditor = false } = {}) {
    if (!this.trackSelection.clear()) return

    if (preserveEditor) {
      this.map.off("click", "track-points", this._handleTrackPointClick)
      this._restoreMainPointsOpacity()
    } else {
      this.clearPointSelection()
    }

    // Close info panel
    if (!preserveEditor) this.controller.closeInfo({ clearSelection: false })
  }

  clearPointSelection() {
    this._clearTrackPointsLayer()
    this._restoreMainPointsOpacity()
  }

  /**
   * Toggle track points layer visibility
   * @param {number} trackId - Track ID
   * @param {boolean} enabled - Whether to show or hide points
   */
  async _toggleTrackPoints(trackId, enabled) {
    if (enabled) {
      // Dim the main points layer
      this._setMainPointsOpacity(0.3)

      const mapEditor = await this._mapEditor()
      await mapEditor.selectTrack(trackId)

      // Register click handler for track points (shows point info on click)
      this.map.on("click", "track-points", this._handleTrackPointClick)
    } else {
      // Clear track points layer
      this._clearTrackPointsLayer()

      // Restore main points layer opacity
      this._restoreMainPointsOpacity()
    }
  }

  /**
   * Clear the track points layer and remove its click handler
   */
  _clearTrackPointsLayer() {
    // Remove the click handler before clearing the layer
    this.map.off("click", "track-points", this._handleTrackPointClick)

    this.controller.layerManager.getLayer("map-editor")?.clear()
  }

  async _mapEditor() {
    let editor = this.controller.layerManager.getLayer("map-editor")
    if (editor) return editor

    const { MapEditor } = await import("maps_maplibre/editing/map_editor")
    editor = new MapEditor(this.map, {
      apiClient: this.controller.api,
      layerManager: this.controller.layerManager,
      editable: this._pointEditingEnabled(),
      distanceUnit: this.controller.settings?.distance_unit || "km",
      historyScope: () => ({
        startAt: this.controller.startDateValue,
        endAt: this.controller.endDateValue,
      }),
    })
    this.controller.layerManager.registerLayer("map-editor", editor)
    return editor
  }

  _pointEditingEnabled() {
    return (
      SettingsManager.getSetting("pointDraggingEnabled") === true &&
      !isGatedPlan(this.controller?.userPlanValue)
    )
  }

  canDragPoint(properties) {
    return this.pointDrag.canDrag(properties)
  }

  async _openPointEditor(feature) {
    const editor = await this._mapEditor()
    if (feature.properties.track_id) {
      await editor.selectTrack(feature.properties.track_id, {
        forEditing: true,
      })
    } else {
      editor.selectPoint(feature, { forEditing: true })
    }
  }

  /**
   * Undo the dimming of a point selection, keeping a highlighted day dimmed.
   */
  _restoreMainPointsOpacity() {
    const highlightedDay = this.controller.timelineBridge?.highlightedDay
    if (highlightedDay) {
      this.controller.timelineBridge.applyDayHighlight(highlightedDay)
    } else {
      this._setMainPointsOpacity(1.0)
    }
  }

  /**
   * Set the opacity of the main points layer
   * @param {number} opacity - Opacity value (0-1)
   */
  _setMainPointsOpacity(opacity) {
    if (this.map.getLayer("points-mvt")) {
      this.map.setPaintProperty("points-mvt", "circle-opacity", opacity)
      this.map.setPaintProperty("points-mvt", "circle-stroke-opacity", opacity)
    }
  }
}

// TrackSelection stays in this file: the protected spec/regressions harnesses
// load event_handlers.js on its own and construct EventHandlers from it.
function parseSegments(properties) {
  try {
    return typeof properties.segments === "string"
      ? JSON.parse(properties.segments)
      : properties.segments || []
  } catch (err) {
    console.warn("Failed to parse track segments:", err)
    return []
  }
}

function createEmojiMarker(emoji, markerClass = "route-emoji-marker") {
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
