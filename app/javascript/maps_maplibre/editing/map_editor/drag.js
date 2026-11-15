import { translate } from "i18n"
import { Toast } from "maps_maplibre/components/toast"
import { clone, snapshotCoordinates } from "../editable_track_data"
import { MOUSE_DRAG_THRESHOLD_PX } from "../point_drag_gesture"

/**
 * Dragging a point: mouse threshold, live preview and saving the move.
 * Mixed into MapEditor; `this` is the MapEditor.
 */
export const editorDrag = {
  onMouseDown(event) {
    if (!event.features?.[0]) return
    if (!this.startDrag(Number(event.features[0].properties.id))) return
    event.preventDefault()
    this.pressPoint = event.point
    this.map.on("mousemove", this._onMouseMove)
    this.map.once("mouseup", this._onMouseUp)
  },

  onMouseMove(event) {
    if (!this.hasMoved && this._withinDragThreshold(event.point)) return
    this.dragTo(event.lngLat.lng, event.lngLat.lat)
  },

  _withinDragThreshold(point) {
    const start = this.pressPoint
    return (
      Math.hypot(point.x - start.x, point.y - start.y) < MOUSE_DRAG_THRESHOLD_PX
    )
  },

  onMouseUp(event) {
    this.map.off("mousemove", this._onMouseMove)
    return this.endDrag(event.lngLat)
  },

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
  },

  dragTo(longitude, latitude) {
    if (this.draggedPointId == null) return
    this.hasMoved = true
    this.preview(this.draggedPointId, longitude, latitude)
  },

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
  },

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
      this._updateUncoveredTrack()
    }
    this.layer.setData(this.data)
    this._syncSelectedTrack(track)
  },

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
  },

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
  },
}
