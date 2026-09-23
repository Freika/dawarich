import { translate } from "i18n"
import { Toast } from "maps_maplibre/components/toast"
import { EditableTrackLayer } from "../layers/editable_track_layer"
import { EditSuccessIndicator } from "./edit_success_indicator"
import {
  clone,
  pointFeature,
  segmentFeature,
  snapshotCoordinates,
  updateSegmentGeometry,
} from "./editable_track_data"
import { EditorHistory } from "./editor_history"
import { TileExclusions } from "./tile_exclusions"

export class MapEditor {
  constructor(
    map,
    {
      apiClient,
      layerManager,
      historyScope,
      editable = true,
      distanceUnit = "km",
    } = {},
  ) {
    this.map = map
    this.apiClient = apiClient
    this.importScoped = Boolean(apiClient?.importId)
    this.layerManager = layerManager
    this.mutationState = layerManager.pointMutationState ||= { busy: false }
    this.disposed = false
    this.historyScope = historyScope
    this.editable = editable
    this.layer = new EditableTrackLayer(map)
    this.indicator = new EditSuccessIndicator(map, this.layer.successLayerId)
    this.exclusions = new TileExclusions(map)
    this.trackLoad = null
    this.edits = new EditorHistory(this, { distanceUnit })
    this.inFlight = false
    this.inFlightKeys = new Set()
    this.sessionVersion = 0
    this.justDragged = false
    this._onMouseDown = this.onMouseDown.bind(this)
    this._onMouseMove = this.onMouseMove.bind(this)
    this._onMouseUp = this.onMouseUp.bind(this)
  }

  async selectTrack(trackId, { forEditing = false } = {}) {
    this.close()
    const sessionVersion = this.sessionVersion
    const [track, points] = await this._fetchTrack(trackId)
    if (sessionVersion !== this.sessionVersion) return false

    this.forEditing = forEditing
    this._showTrack(trackId, track, points)
    if (this.editable) this._enableDragging()
    return true
  }

  // Starts dragging a point straight from the tile layer. Its track loads in
  // the background: the line follows once it arrives, and saving waits for
  // it because the server requires the track revision.
  beginTileDrag(feature) {
    if (!this.editable || this.disposed || this.mutationState.busy) return false
    this.selectPoint(feature, { forEditing: true })
    const trackId = feature.properties?.track_id
    if (trackId != null)
      this.trackLoad = this._loadTrackDuringDrag(trackId, this.sessionVersion)
    return this.startDrag(Number(feature.properties.id))
  }

  _fetchTrack(trackId) {
    return Promise.all([
      this.apiClient.fetchTrackWithSegments(trackId, { geometry: "original" }),
      this.apiClient.fetchTrackPoints(trackId),
    ])
  }

  _showTrack(trackId, track, points) {
    if (!track) throw new Error(`Track ${trackId} was not found`)

    this.trackId = Number(trackId)
    this.trackRevision = Number(track.properties.revision || 0)
    const data = {
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
    if (this.data) this.layer.setData(data)
    else this.layer.add(data)
    this.data = data
    this._excludeTiles()
  }

  async _loadTrackDuringDrag(trackId, sessionVersion) {
    try {
      const [track, points] = await this._fetchTrack(trackId)
      if (sessionVersion !== this.sessionVersion || !track) return

      const draggedId = this.draggedPointId
      const dragged = draggedId != null && this._point(draggedId)
      const coordinates = dragged && [...dragged.geometry.coordinates]
      this.exclusions.restore()
      this._showTrack(trackId, track, points)
      if (draggedId == null) return
      this.snapshot = clone(this.data)
      if (this.hasMoved && coordinates) this.preview(draggedId, ...coordinates)
    } catch (error) {
      console.warn(
        "[MapEditor] Failed to load the dragged point's track:",
        error,
      )
    }
  }

  selectPoint(feature, { forEditing = false } = {}) {
    this.close()
    this.forEditing = forEditing
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
    this._excludeTiles()
    if (this.editable) this._enableDragging()
  }

  setEditable(editable) {
    this.editable = editable === true
    this.map.off("mousedown", "track-points", this._onMouseDown)
    this.edits.sync()
    if (!this.editable && this.forEditing) {
      this.close()
      return
    }
    if (this.editable && this.data) this._enableDragging()
  }

  onMouseDown(event) {
    if (!event.features?.[0]) return
    if (!this.startDrag(Number(event.features[0].properties.id))) return
    event.preventDefault()
    this.map.on("mousemove", this._onMouseMove)
    this.map.once("mouseup", this._onMouseUp)
  }

  onMouseMove(event) {
    this.dragTo(event.lngLat.lng, event.lngLat.lat)
  }

  onMouseUp(event) {
    this.map.off("mousemove", this._onMouseMove)
    return this.endDrag(event.lngLat)
  }

  startDrag(pointId) {
    if (
      !this.editable ||
      this.disposed ||
      this.inFlight ||
      this.mutationState.busy ||
      !this.data ||
      !this._point(pointId)
    )
      return false
    if (this.inFlightKeys.has(this._mutationKey(pointId))) return false
    this.draggedPointId = pointId
    this.snapshot = clone(this.data)
    this.hasMoved = false
    this.map.getCanvasContainer().style.cursor = "grabbing"
    this.edits.sync()
    return true
  }

  dragTo(longitude, latitude) {
    if (this.draggedPointId == null) return
    this.hasMoved = true
    this.preview(this.draggedPointId, longitude, latitude)
  }

  cancelDrag() {
    if (this.draggedPointId == null) return
    this.map.off("mousemove", this._onMouseMove)
    this.map.getCanvasContainer().style.cursor = ""
    if (this.snapshot) {
      this.data = this.snapshot
      this.layer.setData(this.data)
      this._syncSelectedTrack(this._track())
    }
    this.draggedPointId = null
    this.snapshot = null
    this.hasMoved = false
    this.edits.sync()
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
    this._syncSelectedTrack(track)
  }

  async endDrag(lngLat) {
    this.map.getCanvasContainer().style.cursor = ""
    if (!this.hasMoved || this.draggedPointId == null) {
      this.draggedPointId = null
      this.edits.sync()
      return
    }

    const pointId = this.draggedPointId
    const sessionVersion = this.sessionVersion
    const mutationKey = this._mutationKey(pointId)
    this.preview(pointId, lngLat.lng, lngLat.lat)
    this.justDragged = true
    setTimeout(() => {
      this.justDragged = false
    }, 0)
    this.inFlight = true
    this.mutationState.busy = true
    this.edits.sync()
    this.inFlightKeys.add(mutationKey)

    try {
      if (this.trackLoad) await this.trackLoad
      if (sessionVersion !== this.sessionVersion) return
      const point = this._point(pointId)
      const original = snapshotCoordinates(this.snapshot, pointId)
      const response = await this.apiClient.movePointPosition(pointId, {
        latitude: point.geometry.coordinates[1],
        longitude: point.geometry.coordinates[0],
        pointRevision: Number(point.properties.revision || 0),
        trackRevision: this.trackRevision,
        historyScope: this.historyScope(),
      })
      this._afterMove(response, sessionVersion, pointId)
      if (original)
        this.edits.record(
          {
            pointId,
            from: original,
            to: {
              longitude: point.geometry.coordinates[0],
              latitude: point.geometry.coordinates[1],
            },
          },
          response,
        )
    } catch (error) {
      if (sessionVersion !== this.sessionVersion) return
      if (error.status === 409 && error.payload?.point)
        this.applyCanonical(error.payload)
      else {
        this.data = this.snapshot
        this.layer.setData(this.data)
        this._syncSelectedTrack(this._track())
      }
      const message =
        error.status === 409
          ? "messages.point_edit_conflict"
          : "messages.failed_to_update_point_position_please_try_again"
      Toast.error(translate(message))
    } finally {
      this.mutationState.busy = false
      this.inFlightKeys.delete(mutationKey)
      if (sessionVersion === this.sessionVersion) {
        this.inFlight = false
        this.draggedPointId = null
        this.snapshot = null
      }
      this.edits.sync()
    }
  }

  _afterMove(response, sessionVersion, pointId) {
    this.layerManager.controller?.mapDataManager?.invalidatePoints()
    const isCurrentSession = sessionVersion === this.sessionVersion
    if (isCurrentSession) this.applyCanonical(response, { rejectStale: true })
    else this._syncSelectedTrack(response.track)
    this.layerManager.getLayer("points-mvt")?.refresh()
    this.layerManager.getLayer("tracks-mvt")?.refresh()
    this.reapplyTileFilters()
    if (isCurrentSession) this.indicator.show(pointId)
    if (isCurrentSession && this.importScoped && this.trackId != null)
      void this._refreshSelectedImportTrack(sessionVersion)
    document.dispatchEvent(
      new CustomEvent("dawarich:point-moved", { detail: response }),
    )
  }

  applyCanonical(response, { rejectStale = false } = {}) {
    if (!this.data) return false

    const canonicalPoint = response.point
    const canonicalTrack = response.track
    if (!canonicalPoint) return false
    if (rejectStale && this._responseIsStale(response)) return false

    const point = this._point(canonicalPoint.id)
    if (point) Object.assign(point, pointFeature(canonicalPoint, this.trackId))
    if (
      canonicalTrack &&
      Number(canonicalTrack.properties.id) === this.trackId
    ) {
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
    this._syncSelectedTrack(canonicalTrack)
    return true
  }

  _syncSelectedTrack(feature) {
    if (this.importScoped || !feature) return
    const layer = this.layerManager.getLayer("tracks")
    const selected = layer?.selectedFeature
    if (
      !selected ||
      Number(selected.properties?.id) !== Number(feature.properties?.id)
    )
      return
    const selectedRevision = Number(selected.properties?.revision || 0)
    const featureRevision = Number(feature.properties?.revision || 0)
    if (featureRevision < selectedRevision) return
    layer.setSelectedTrack(clone(feature))
  }

  applyRealtime(response) {
    if (!this.data) return false

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
      const feature = await this.apiClient.fetchTrackWithSegments(
        this.trackId,
        {
          geometry: "original",
        },
      )
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
    this.exclusions.restore()
    this.layer.remove()
    this.data = null
    this.forEditing = false
    this.trackLoad = null
    this.trackId = null
    this.inFlight = false
    this.draggedPointId = null
    this.snapshot = null
    this.hasMoved = false
    this.edits.sync()
  }

  dispose() {
    this.disposed = true
    this.close()
  }

  clear() {
    this.close()
  }

  reapplyTileFilters() {
    if (!this.data) return
    this._excludeTiles()
  }

  _excludeTiles() {
    this.exclusions.apply({
      trackId: this.importScoped ? null : this.trackId,
      pointIds: this._points().map((point) => Number(point.properties.id)),
    })
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
    updateSegmentGeometry(this._points(), this._segments())
  }
}
