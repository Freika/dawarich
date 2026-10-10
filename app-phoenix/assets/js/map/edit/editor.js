import { createRequestScope } from "../data/request_scope.js"
import { clone, snapshotCoordinates } from "./editable_track_data.js"
import { EditableTrackLayer } from "./editable_track_layer.js"
import { EditorHistory } from "./editor_history.js"
import { EditSuccessIndicator } from "./success_indicator.js"
import { TileExclusions } from "./tile_exclusions.js"
import { TrackSession } from "./track_session.js"

export class MapEditor extends TrackSession {
  constructor(
    map,
    {
      readTrack,
      readPoints,
      move,
      importScoped = false,
      historyScope = () => ({}),
      editable = true,
      distanceUnit = "km",
      history = null,
      mutationState = { busy: false },
      getSelectedTrack = () => null,
      setSelectedTrack = () => {},
      invalidatePoints = () => {},
      refreshTiles = () => {},
      clearSelection = () => {},
      onError = () => {},
      onMoved = () => {},
      translate = (key) => key,
      document = globalThis.document,
      createLayer = (map) => new EditableTrackLayer(map),
      createIndicator = (map, id) => new EditSuccessIndicator(map, id),
    } = {},
  ) {
    super()
    Object.assign(this, {
      map,
      readTrack,
      readPoints,
      move,
      importScoped,
      historyScope,
      editable,
      mutationState,
      getSelectedTrack,
      setSelectedTrack,
      invalidatePoints,
      refreshTiles,
      clearSelection,
      onError,
      onMoved,
      translate,
      document,
    })
    this.disposed = false
    this.layer = createLayer(map)
    this.indicator = createIndicator(map, this.layer.successLayerId)
    this.exclusions = new TileExclusions(map)
    this.readScope = createRequestScope()
    this.trackLoad = null
    this.edits = new EditorHistory(this, { distanceUnit, history })
    this.inFlight = false
    this.inFlightKeys = new Set()
    this.sessionVersion = 0
    this.justDragged = false
    this._onMouseDown = this.onMouseDown.bind(this)
    this._onMouseMove = this.onMouseMove.bind(this)
    this._onMouseUp = this.onMouseUp.bind(this)
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
    this.dragTimer = setTimeout(() => {
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
      const response = await this.move(pointId, {
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
      this.onError(this.translate(message))
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
    if (this.disposed) return
    this.invalidatePoints()
    const isCurrentSession = sessionVersion === this.sessionVersion
    if (isCurrentSession) this.applyCanonical(response, { rejectStale: true })
    else this._syncSelectedTrack(response.track)
    this.refreshTiles()
    this.reapplyTileFilters()
    if (isCurrentSession) this.indicator.show(pointId)
    if (isCurrentSession && this.importScoped && this.trackId != null)
      void this._refreshSelectedImportTrack(sessionVersion)
    this.onMoved(response)
  }

  close() {
    this.sessionVersion += 1
    this.readScope.reset()
    clearTimeout(this.dragTimer)
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
    this.readScope.destroy()
  }

  clear() {
    this.close()
  }

  _enableDragging() {
    this.map.off("mousedown", "track-points", this._onMouseDown)
    this.map.on("mousedown", "track-points", this._onMouseDown)
  }

  _mutationKey(pointId) {
    return this.trackId == null ? `point:${pointId}` : `track:${this.trackId}`
  }
}
