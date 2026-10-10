import { clone } from "./editable_track_data.js"
import { EditorGeometry } from "./geometry.js"

export class TrackSession extends EditorGeometry {
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

  async _fetchTrack(trackId) {
    const operation = this.readScope.begin()
    try {
      const result = await operation.wait(
        Promise.all([
          this.readTrack(trackId, { signal: operation.signal }),
          this.readPoints(trackId, { signal: operation.signal }),
        ]),
      )
      operation.check()
      return result
    } finally {
      operation.close()
    }
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
    } catch (_error) {
      this.onError(
        this.translate(
          "messages.failed_to_update_point_position_please_try_again",
        ),
      )
    }
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
      const feature = await this.readTrack(this.trackId)
      if (sessionVersion !== this.sessionVersion) return
      this.setSelectedTrack(feature)
    } catch (_error) {
      if (sessionVersion !== this.sessionVersion) return
      this.setSelectedTrack(null)
      this.onError(
        this.translate(
          "messages.failed_to_update_point_position_please_try_again",
        ),
      )
    }
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

  _clearSelectedTrack() {
    this.clearSelection()
  }
}
