import { translate } from "i18n"
import { Toast } from "maps_maplibre/components/toast"
import { EditableTrackLayer } from "../layers/editable_track_layer"
import { EditSuccessIndicator } from "./edit_success_indicator"

function clone(value) {
  return JSON.parse(JSON.stringify(value))
}

function pointFeature(point, trackId) {
  const properties = { ...point, id: Number(point.id), kind: "point" }
  if (trackId != null) properties.track_id = Number(trackId)

  return {
    type: "Feature",
    geometry: {
      type: "Point",
      coordinates: [Number(point.longitude), Number(point.latitude)],
    },
    properties,
  }
}

function segmentFeature(segment) {
  return {
    type: "Feature",
    geometry: { type: "LineString", coordinates: segment.coordinates || [] },
    properties: { ...segment, id: Number(segment.id), kind: "segment" },
  }
}

export class MapEditor {
  constructor(
    map,
    { apiClient, layerManager, historyScope, editable = true } = {},
  ) {
    this.map = map
    this.apiClient = apiClient
    this.importScoped = Boolean(apiClient?.importId)
    this.layerManager = layerManager
    this.historyScope = historyScope
    this.editable = editable
    this.layer = new EditableTrackLayer(map)
    this.indicator = new EditSuccessIndicator(map, this.layer.successLayerId)
    this.inFlight = false
    this.inFlightKeys = new Set()
    this.sessionVersion = 0
    this.justDragged = false
    this._onMouseDown = this.onMouseDown.bind(this)
    this._onMouseMove = this.onMouseMove.bind(this)
    this._onMouseUp = this.onMouseUp.bind(this)
  }

  async selectTrack(trackId) {
    this.close()
    const sessionVersion = this.sessionVersion
    const [track, points] = await Promise.all([
      this.apiClient.fetchTrackWithSegments(trackId),
      this.apiClient.fetchTrackPoints(trackId),
    ])
    if (sessionVersion !== this.sessionVersion) return false
    if (!track) throw new Error(`Track ${trackId} was not found`)

    this.trackId = Number(trackId)
    this.trackRevision = Number(track.properties.revision || 0)
    this.data = {
      type: "FeatureCollection",
      features: [
        ...(!this.importScoped
          ? [
              { ...track, properties: { ...track.properties, kind: "track" } },
              ...(track.properties.segments || []).map(segmentFeature),
            ]
          : []),
        ...points.map((point) => pointFeature(point, trackId)),
      ],
    }
    this.layer.add(this.data)
    this._hideTileFeatures()
    if (this.editable) this._enableDragging()
    return true
  }

  selectPoint(feature) {
    this.close()
    const properties = feature.properties || {}
    this.trackId = null
    this.trackRevision = null
    this.data = {
      type: "FeatureCollection",
      features: [
        {
          type: "Feature",
          geometry: {
            type: "Point",
            coordinates: [
              Number(properties.longitude),
              Number(properties.latitude),
            ],
          },
          properties: {
            ...properties,
            id: Number(properties.id),
            kind: "point",
          },
        },
      ],
    }
    this.layer.add(this.data)
    this._hideTileFeatures()
    if (this.editable) this._enableDragging()
  }

  setEditable(editable) {
    this.editable = editable === true
    this.map.off("mousedown", "track-points", this._onMouseDown)
    if (this.editable && this.data) this._enableDragging()
  }

  onMouseDown(event) {
    if (this.inFlight || !event.features?.[0]) return
    const pointId = Number(event.features[0].properties.id)
    if (this.inFlightKeys.has(this._mutationKey(pointId))) return
    event.preventDefault()
    this.draggedPointId = pointId
    this.snapshot = clone(this.data)
    this.hasMoved = false
    this.map.getCanvasContainer().style.cursor = "grabbing"
    this.map.on("mousemove", this._onMouseMove)
    this.map.once("mouseup", this._onMouseUp)
  }

  onMouseMove(event) {
    if (!this.draggedPointId) return
    this.hasMoved = true
    this.preview(this.draggedPointId, event.lngLat.lng, event.lngLat.lat)
  }

  preview(pointId, longitude, latitude) {
    const point = this._point(pointId)
    if (!point) return
    point.geometry.coordinates = [longitude, latitude]
    point.properties.longitude = String(longitude)
    point.properties.latitude = String(latitude)
    const track = this._track()
    if (track) {
      track.geometry.coordinates = this._points().map(
        (feature) => feature.geometry.coordinates,
      )
      this._updateSegments()
    }
    this.layer.setData(this.data)
  }

  async onMouseUp(event) {
    this.map.off("mousemove", this._onMouseMove)
    this.map.getCanvasContainer().style.cursor = ""
    if (!this.hasMoved || !this.draggedPointId) {
      this.draggedPointId = null
      return
    }

    const pointId = this.draggedPointId
    const sessionVersion = this.sessionVersion
    const mutationKey = this._mutationKey(pointId)
    this.preview(pointId, event.lngLat.lng, event.lngLat.lat)
    this.justDragged = true
    setTimeout(() => {
      this.justDragged = false
    }, 0)
    this.inFlight = true
    this.inFlightKeys.add(mutationKey)

    try {
      const point = this._point(pointId)
      const response = await this.apiClient.movePointPosition(pointId, {
        latitude: point.geometry.coordinates[1],
        longitude: point.geometry.coordinates[0],
        pointRevision: Number(point.properties.revision || 0),
        trackRevision: this.trackRevision,
        historyScope: this.historyScope(),
      })
      const isCurrentSession = sessionVersion === this.sessionVersion
      if (isCurrentSession) this.applyCanonical(response, { rejectStale: true })
      this.layerManager.getLayer("points-mvt")?.refresh()
      this.layerManager.getLayer("tracks-mvt")?.refresh()
      this.reapplyTileFilters()
      if (isCurrentSession) this.indicator.show(pointId)
      if (isCurrentSession && this.importScoped && this.trackId != null)
        void this._refreshSelectedImportTrack(sessionVersion)
      document.dispatchEvent(
        new CustomEvent("dawarich:point-moved", { detail: response }),
      )
    } catch (error) {
      if (sessionVersion !== this.sessionVersion) return
      if (error.status === 409 && error.payload?.point)
        this.applyCanonical(error.payload)
      else {
        this.data = this.snapshot
        this.layer.setData(this.data)
      }
      const message =
        error.status === 409
          ? "messages.point_edit_conflict"
          : "messages.failed_to_update_point_position_please_try_again"
      Toast.error(translate(message))
    } finally {
      this.inFlightKeys.delete(mutationKey)
      if (sessionVersion === this.sessionVersion) {
        this.inFlight = false
        this.draggedPointId = null
        this.snapshot = null
      }
    }
  }

  applyCanonical(response, { rejectStale = false } = {}) {
    const canonicalPoint = response.point
    const canonicalTrack = response.track
    if (!canonicalPoint) return false
    if (rejectStale && this._responseIsStale(response)) return false

    const point = this._point(canonicalPoint.id)
    if (point) Object.assign(point, pointFeature(canonicalPoint, this.trackId))
    if (canonicalTrack) {
      const track = this._track()
      if (track) {
        track.geometry = clone(canonicalTrack.geometry)
        track.properties = { ...canonicalTrack.properties, kind: "track" }
        this.data.features = this.data.features.filter(
          (feature) => feature.properties.kind !== "segment",
        )
        this.data.features.splice(
          1,
          0,
          ...(canonicalTrack.properties.segments || []).map(segmentFeature),
        )
      }
      this.trackRevision = Number(
        response.revision?.track ?? canonicalTrack.properties.revision,
      )
    }
    this.layer.setData(this.data)
    return true
  }

  applyRealtime(response) {
    const responseTrackId = response.track?.properties?.id
    const sameTrack =
      responseTrackId != null && Number(responseTrackId) === this.trackId
    const activePoint = response.point && this._point(response.point.id)
    if (!sameTrack && !activePoint) return false

    const revision = sameTrack
      ? Number(response.revision?.track || 0)
      : Number(response.revision?.point || 0)
    const currentRevision = sameTrack
      ? this.trackRevision
      : Number(activePoint.properties.revision || 0)
    if (revision <= currentRevision) return false
    this.applyCanonical(response)
    if (this.importScoped && this.trackId != null)
      void this._refreshSelectedImportTrack(this.sessionVersion)
    return true
  }

  async _refreshSelectedImportTrack(sessionVersion) {
    try {
      const feature = await this.apiClient.fetchTrackWithSegments(this.trackId)
      if (sessionVersion !== this.sessionVersion) return
      this.layerManager.getLayer("tracks")?.setSelectedTrack(feature)
    } catch (error) {
      if (sessionVersion !== this.sessionVersion) return
      this.layerManager.getLayer("tracks")?.setSelectedTrack(null)
      console.warn("Failed to refresh imported track highlight:", error)
    }
  }

  close() {
    this.sessionVersion += 1
    this.indicator.cancel()
    this.map.off("mousemove", this._onMouseMove)
    this.map.off("mouseup", this._onMouseUp)
    this.map.off("mousedown", "track-points", this._onMouseDown)
    this._restoreTileFilters()
    this.layer.remove()
    this.data = null
    this.trackId = null
    this.inFlight = false
    this.draggedPointId = null
    this.snapshot = null
    this.hasMoved = false
  }

  clear() {
    this.close()
  }

  // Tile refreshes replace MapLibre sources and therefore discard their
  // filters. Re-capture the canonical base filters (for example flight masks)
  // and put the focused edit exclusions back on top.
  reapplyTileFilters() {
    if (!this.data) return
    this._hideTileFeatures()
  }

  _enableDragging() {
    this.map.off("mousedown", "track-points", this._onMouseDown)
    this.map.on("mousedown", "track-points", this._onMouseDown)
  }

  _track() {
    return this.data.features.find(
      (feature) => feature.properties.kind === "track",
    )
  }
  _segments() {
    return this.data.features.filter(
      (feature) => feature.properties.kind === "segment",
    )
  }
  _points() {
    return this.data.features.filter(
      (feature) => feature.properties.kind === "point",
    )
  }
  _point(id) {
    return this._points().find(
      (feature) => Number(feature.properties.id) === Number(id),
    )
  }

  _mutationKey(pointId) {
    return this.trackId == null ? `point:${pointId}` : `track:${this.trackId}`
  }

  _responseIsStale(response) {
    if (response.track && this.trackId != null) {
      return (
        Number(response.revision?.track || 0) < Number(this.trackRevision || 0)
      )
    }
    const activePoint = this._point(response.point?.id)
    return (
      activePoint &&
      Number(response.revision?.point || 0) <
        Number(activePoint.properties.revision || 0)
    )
  }

  _updateSegments() {
    const points = this._points()
    for (const segment of this._segments()) {
      const { start_index: startIndex, end_index: endIndex } =
        segment.properties
      let segmentPoints
      if (startIndex != null && endIndex != null) {
        segmentPoints = points.slice(Number(startIndex), Number(endIndex) + 1)
      } else {
        const start = Number(segment.properties.start_time)
        const end = Number(segment.properties.end_time)
        segmentPoints = points.filter((point) => {
          const timestamp = Number(point.properties.timestamp)
          return timestamp >= start && timestamp <= end
        })
      }
      segment.geometry.coordinates = segmentPoints.map(
        (point) => point.geometry.coordinates,
      )
    }
  }

  _hideTileFeatures() {
    this.previousTrackFilter = this.map.getFilter?.("tracks-mvt") || null
    this.previousPointFilter = this.map.getFilter?.("points-mvt") || null
    if (this.trackId && !this.importScoped && this.map.getLayer("tracks-mvt")) {
      const exclusion = ["!=", ["get", "id"], this.trackId]
      this.map.setFilter(
        "tracks-mvt",
        this.previousTrackFilter
          ? ["all", this.previousTrackFilter, exclusion]
          : exclusion,
      )
    }
    if (this.map.getLayer("points-mvt")) {
      const exclusion = [
        "!",
        [
          "in",
          ["get", "id"],
          [
            "literal",
            this._points().map((point) => Number(point.properties.id)),
          ],
        ],
      ]
      this.map.setFilter(
        "points-mvt",
        this.previousPointFilter
          ? ["all", this.previousPointFilter, exclusion]
          : exclusion,
      )
    }
  }

  _restoreTileFilters() {
    if (this.map.getLayer("tracks-mvt"))
      this.map.setFilter("tracks-mvt", this.previousTrackFilter)
    if (this.map.getLayer("points-mvt"))
      this.map.setFilter("points-mvt", this.previousPointFilter)
  }
}
