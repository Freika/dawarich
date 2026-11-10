/**
 * Spreading a cluster's photos around its centre and drawing the legs back to it.
 * Mixed into PhotosLayer; `this` is the PhotosLayer.
 */
export const photoSpider = {
  /**
   * Tiled source features carry Web Mercator geometry, clamped to ±85.05°
   * latitude. The globe can show the poles, so read the photo's real position
   * from the layer data there; the flat map keeps the clamped position, which
   * stays inside the Mercator world.
   */
  _originalCoordinates(feature) {
    if (this.map.getProjection?.()?.type !== "globe") {
      return feature.geometry.coordinates
    }
    if (!this._coordinatesById || this._coordinatesData !== this.data) {
      this._coordinatesData = this.data
      this._coordinatesById = new Map(
        (this.data?.features ?? []).map((f) => [
          f.properties?.id,
          f.geometry.coordinates,
        ]),
      )
    }
    return (
      this._coordinatesById.get(feature.properties?.id) ??
      feature.geometry.coordinates
    )
  },

  /**
   * Group nearby features and compute offset positions so markers don't overlap.
   * Uses a spiral layout that scales well for large groups (60+ photos).
   * Returns a Map of featureId -> [offsetLng, offsetLat] for features that need moving.
   */
  _computeSpiderOffsets(visibleFeatures) {
    const offsets = new Map()
    const OVERLAP_PX = 40

    // Convert each feature to screen coordinates for proximity grouping
    const entries = []
    for (const [id, feature] of visibleFeatures) {
      const [lng, lat] = this._originalCoordinates(feature)
      const point = this.map.project([lng, lat])
      entries.push({ id, lng, lat, px: point.x, py: point.y })
    }

    // Group features by proximity using a simple greedy approach
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

    // For each overlapping group, compute spiral positions
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
  },

  /**
   * Compute spiral positions for N items around a center point.
   * Places items in concentric rings, each ring fitting more items,
   * with enough spacing so 50px markers don't overlap.
   */
  _computeSpiralPositions(count, center) {
    const MARKER_SIZE = 50
    const SPACING = 8
    const step = MARKER_SIZE + SPACING // distance between marker centers
    const positions = []

    if (count <= 8) {
      // Small group: single circle
      const radius = Math.max(step, (count * step) / (2 * Math.PI))
      for (let i = 0; i < count; i++) {
        const angle = (2 * Math.PI * i) / count - Math.PI / 2
        positions.push({
          x: center.x + radius * Math.cos(angle),
          y: center.y + radius * Math.sin(angle),
        })
      }
    } else {
      // Large group: concentric rings
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
  },

  /**
   * Create or update a spider leg line from a photo's original position to its offset position.
   * Reuses existing source/layer if one already exists for this feature id.
   */
  _updateLeg(featureId, origin, offset) {
    const lineData = {
      type: "Feature",
      geometry: { type: "LineString", coordinates: [origin, offset] },
    }

    const legId = this.legCache.get(featureId)
    if (legId) {
      // Update existing leg
      const source = this.map.getSource(legId)
      if (source) {
        source.setData(lineData)
        return
      }
    }

    // Create new leg
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
    } catch (_e) {
      // Silently ignore if source/layer already exists from a race
    }
  },

  /**
   * Remove a spider leg line for a given feature id
   */
  _removeLeg(featureId) {
    const legId = this.legCache.get(featureId)
    if (!legId) return

    if (this.map.getLayer(legId)) this.map.removeLayer(legId)
    if (this.map.getSource(legId)) this.map.removeSource(legId)
    this.legCache.delete(featureId)
  },

  /**
   * Remove all spider leg lines
   */
  _clearAllLegs() {
    for (const [id] of this.legCache) {
      this._removeLeg(id)
    }
  },
}
