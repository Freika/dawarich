import { EditableTrackLayer } from "../layers/editable_track_layer"
import { EditSuccessIndicator } from "./edit_success_indicator"
import {
  clone,
  pointFeature,
  segmentFeature,
  uncoveredTrackFeature,
  updateSegmentGeometry,
} from "./editable_track_data"
import { EditorHistory } from "./editor_history"
import { editorDrag } from "./map_editor/drag"
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
    if (forEditing) this._clearSelectedTrack()
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
    if (trackId != null) {
      this.trackId = Number(trackId)
      this._excludeTiles()
      this.trackLoad = this._loadTrackDuringDrag(trackId, this.sessionVersion)
    }
    return this.startDrag(Number(feature.properties.id))
  }

  _fetchTrack(trackId) {
    return Promise.all([
      this.apiClient.fetchTrackWithSegments(trackId, { unmasked: true }),
      this.apiClient.fetchTrackPoints(trackId, { unmasked: true }),
    ])
  }

  _showTrack(trackId, track, points) {
    if (!track) throw new Error(`Track ${trackId} was not found`)

    this.trackId = Number(trackId)
    this.trackRevision = Number(track.properties.revision || 0)
    const pointFeatures = points.map((point) => pointFeature(point, trackId))
    const segmentFeatures = (track.properties.segments || []).map(
      segmentFeature,
    )
    const uncovered = this.importScoped
      ? null
      : uncoveredTrackFeature(pointFeatures, segmentFeatures)
    const data = {
      type: "FeatureCollection",
      features: [
        ...(!this.importScoped
          ? [
              {
                ...track,
                properties: {
                  ...track.properties,
                  kind: "track",
                  has_segments: (track.properties.segments || []).length > 0,
                },
              },
              ...segmentFeatures,
              ...(uncovered ? [uncovered] : []),
            ]
          : []),
        ...pointFeatures,
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
    if (forEditing) this._clearSelectedTrack()
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
        track.properties = {
          ...canonicalTrack.properties,
          kind: "track",
          has_segments: (canonicalTrack.properties.segments || []).length > 0,
        }
        this.data.features = this.data.features.filter(
          (feature) => feature.properties.kind !== "segment",
        )
        this.data.features.splice(
          1,
          0,
          ...(canonicalTrack.properties.segments || []).map(segmentFeature),
        )
        this._updateUncoveredTrack()
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
          unmasked: true,
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

  _clearSelectedTrack() {
    this.layerManager.controller?.eventHandlers?.clearTrackSelection?.({
      preserveEditor: true,
    })
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

  _updateUncoveredTrack() {
    this.data.features = this.data.features.filter(
      (feature) => feature.properties.kind !== "uncovered-track",
    )
    const track = this._track()
    if (!track?.properties.has_segments) return
    const uncovered = uncoveredTrackFeature(this._points(), this._segments())
    if (uncovered) this.data.features.push(uncovered)
  }
}

Object.assign(MapEditor.prototype, editorDrag)
