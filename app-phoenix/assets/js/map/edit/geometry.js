import { clone, pointFeature, segmentFeature, uncoveredTrackFeature, updateSegmentGeometry } from "./editable_track_data.js"

export class EditorGeometry {
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
    const selected = this.getSelectedTrack()
    if (
      !selected ||
      Number(selected.properties?.id) !== Number(feature.properties?.id)
    )
      return
    const selectedRevision = Number(selected.properties?.revision || 0)
    const featureRevision = Number(feature.properties?.revision || 0)
    if (featureRevision < selectedRevision) return
    this.setSelectedTrack(clone(feature))
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
