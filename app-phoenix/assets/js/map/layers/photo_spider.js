export class PhotoSpider {
  constructor(map, createMarker) {
    this.map = map
    this.createMarker = createMarker
    this.legCache = new Map()
    this._spiderfiedMarkers = []
  }
  expand(leaves, center) {
    this._clearSpiderfiedMarkers()
    const positions = this._computeSpiralPositions(
      leaves.length,
      this.map.project(center),
    )
    leaves.forEach((leaf, i) => {
      const point = this.map.unproject([positions[i].x, positions[i].y])
      const position = [point.lng, point.lat]
      const line = this._createSpiderLeg(center, position)
      if (line) this._spiderfiedMarkers.push({ type: "leg", id: line })
      this._spiderfiedMarkers.push({
        type: "marker",
        ref: this.createMarker(leaf, position),
      })
    })
  }
  destroy() {
    this._clearSpiderfiedMarkers()
    this._clearAllLegs()
  }
  _createSpiderLeg(from, to) {
    const legId = `spider-leg-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`
    try {
      this.map.addSource(legId, {
        type: "geojson",
        data: {
          type: "Feature",
          geometry: { type: "LineString", coordinates: [from, to] },
        },
      })
      this.map.addLayer({
        id: legId,
        type: "line",
        source: legId,
        paint: {
          "line-color": "rgba(59, 130, 246, 0.4)",
          "line-width": 1.5,
        },
      })
      return legId
    } catch (_e) {
      return null
    }
  }
  _clearSpiderfiedMarkers() {
    if (!this._spiderfiedMarkers) return

    for (const item of this._spiderfiedMarkers) {
      if (item.type === "marker") {
        item.ref.remove()
      } else if (item.type === "leg") {
        if (this.map.getLayer(item.id)) this.map.removeLayer(item.id)
        if (this.map.getSource(item.id)) this.map.removeSource(item.id)
      }
    }
    this._spiderfiedMarkers = []
  }
  _computeSpiderOffsets(visibleFeatures) {
    const offsets = new Map()
    const OVERLAP_PX = 40
    const entries = []
    for (const [id, feature] of visibleFeatures) {
      const [lng, lat] = feature.geometry.coordinates
      const point = this.map.project([lng, lat])
      entries.push({ id, lng, lat, px: point.x, py: point.y })
    }
    const assigned = new Set()
    const groups = []

    for (let i = 0; i < entries.length; i++) {
      if (assigned.has(entries[i].id)) continue

      const group = [entries[i]]
      assigned.add(entries[i].id)

      for (let j = i + 1; j < entries.length; j++) {
        if (assigned.has(entries[j].id)) continue

        const dx = entries[i].px - entries[j].px
        const dy = entries[i].py - entries[j].py
        if (Math.sqrt(dx * dx + dy * dy) < OVERLAP_PX) {
          group.push(entries[j])
          assigned.add(entries[j].id)
        }
      }

      if (group.length > 1) {
        groups.push(group)
      }
    }
    for (const group of groups) {
      const centerPx = {
        x: group.reduce((s, e) => s + e.px, 0) / group.length,
        y: group.reduce((s, e) => s + e.py, 0) / group.length,
      }

      const positions = this._computeSpiralPositions(group.length, centerPx)

      group.forEach((entry, i) => {
        const lngLat = this.map.unproject([positions[i].x, positions[i].y])
        offsets.set(entry.id, [lngLat.lng, lngLat.lat])
      })
    }

    return offsets
  }
  _computeSpiralPositions(count, center) {
    const MARKER_SIZE = 50
    const SPACING = 8
    const step = MARKER_SIZE + SPACING
    const positions = []

    if (count <= 8) {
      const radius = Math.max(step, (count * step) / (2 * Math.PI))
      for (let i = 0; i < count; i++) {
        const angle = (2 * Math.PI * i) / count - Math.PI / 2
        positions.push({
          x: center.x + radius * Math.cos(angle),
          y: center.y + radius * Math.sin(angle),
        })
      }
    } else {
      let placed = 0
      let ring = 1

      while (placed < count) {
        const radius = ring * step
        const circumference = 2 * Math.PI * radius
        const fitInRing = Math.min(
          Math.floor(circumference / step),
          count - placed,
        )

        for (let i = 0; i < fitInRing; i++) {
          const angle = (2 * Math.PI * i) / fitInRing - Math.PI / 2
          positions.push({
            x: center.x + radius * Math.cos(angle),
            y: center.y + radius * Math.sin(angle),
          })
          placed++
        }
        ring++
      }
    }

    return positions
  }
  _updateLeg(featureId, origin, offset) {
    const lineData = {
      type: "Feature",
      geometry: { type: "LineString", coordinates: [origin, offset] },
    }

    const legId = this.legCache.get(featureId)
    if (legId) {
      const source = this.map.getSource(legId)
      if (source) {
        source.setData(lineData)
        return
      }
    }
    const newLegId = `photo-leg-${featureId}`
    try {
      this.map.addSource(newLegId, { type: "geojson", data: lineData })
      this.map.addLayer({
        id: newLegId,
        type: "line",
        source: newLegId,
        paint: {
          "line-color": "rgba(59, 130, 246, 0.4)",
          "line-width": 1.5,
          "line-dasharray": [2, 2],
        },
      })
      this.legCache.set(featureId, newLegId)
    } catch (_e) {}
  }
  _removeLeg(featureId) {
    const legId = this.legCache.get(featureId)
    if (!legId) return

    if (this.map.getLayer(legId)) this.map.removeLayer(legId)
    if (this.map.getSource(legId)) this.map.removeSource(legId)
    this.legCache.delete(featureId)
  }
  _clearAllLegs() {
    for (const [id] of this.legCache) {
      this._removeLeg(id)
    }
  }
}
