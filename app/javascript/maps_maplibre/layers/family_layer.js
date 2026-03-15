import { BaseLayer } from "./base_layer"

/**
 * Family layer showing family member locations
 * Each member has unique color
 */
export class FamilyLayer extends BaseLayer {
  constructor(map, options = {}) {
    super(map, { id: "family", ...options })
    this.memberColors = {}
    this._historyFeatures = []
  }

  getSourceConfig() {
    return {
      type: "geojson",
      data: this.data || {
        type: "FeatureCollection",
        features: [],
      },
    }
  }

  getLayerConfigs() {
    return [
      // Member circles
      {
        id: this.id,
        type: "circle",
        source: this.sourceId,
        paint: {
          "circle-radius": 10,
          "circle-color": ["get", "color"],
          "circle-stroke-width": 2,
          "circle-stroke-color": "#ffffff",
          "circle-opacity": 0.9,
        },
      },

      // Member labels
      {
        id: `${this.id}-labels`,
        type: "symbol",
        source: this.sourceId,
        layout: {
          "text-field": ["get", "name"],
          "text-font": ["Open Sans Bold", "Arial Unicode MS Bold"],
          "text-size": 12,
          "text-offset": [0, 1.5],
          "text-anchor": "top",
        },
        paint: {
          "text-color": "#111827",
          "text-halo-color": "#ffffff",
          "text-halo-width": 2,
        },
      },

      // Pulse animation
      {
        id: `${this.id}-pulse`,
        type: "circle",
        source: this.sourceId,
        paint: {
          "circle-radius": [
            "interpolate",
            ["linear"],
            ["zoom"],
            10,
            15,
            15,
            25,
          ],
          "circle-color": ["get", "color"],
          "circle-opacity": [
            "interpolate",
            ["linear"],
            ["get", "lastUpdate"],
            Date.now() - 10000,
            0,
            Date.now(),
            0.3,
          ],
        },
      },
    ]
  }

  getLayerIds() {
    return [
      this.id,
      `${this.id}-labels`,
      `${this.id}-pulse`,
      `${this.id}-history`,
    ]
  }

  /**
   * Update single family member location
   * @param {Object} member - { id, name, latitude, longitude, color }
   */
  updateMember(member) {
    const features = this.data?.features || []
    const memberId = member.user_id || member.id
    const coords = [member.longitude, member.latitude]
    const color = member.color || this.getMemberColor(memberId)

    // Find existing or add new
    const index = features.findIndex((f) => f.properties.id === memberId)

    const feature = {
      type: "Feature",
      geometry: {
        type: "Point",
        coordinates: coords,
      },
      properties: {
        id: memberId,
        name: member.email || member.name,
        email: member.email,
        color: color,
        lastUpdate: Date.now(),
      },
    }

    if (index >= 0) {
      features[index] = feature
    } else {
      features.push(feature)
    }

    this.update({
      type: "FeatureCollection",
      features,
    })

    // Extend the history polyline with the new point
    this.appendToHistory(memberId, coords, color)
  }

  /**
   * Append a coordinate to the history polyline for a member.
   * Creates the polyline if it doesn't exist yet.
   */
  appendToHistory(memberId, coords, color) {
    const historySourceId = `${this.sourceId}-history`
    const source = this.map.getSource(historySourceId)
    if (!source) return

    const features = [...this._historyFeatures]

    const index = features.findIndex((f) => f.properties.userId === memberId)

    if (index >= 0) {
      // Append coordinate to existing polyline
      features[index] = {
        ...features[index],
        geometry: {
          type: "LineString",
          coordinates: [...features[index].geometry.coordinates, coords],
        },
      }
    } else {
      // No existing polyline — store the point so the next update creates a line
      // A LineString needs at least 2 coordinates, so track pending starts
      if (!this._pendingHistoryStarts) this._pendingHistoryStarts = {}

      if (this._pendingHistoryStarts[memberId]) {
        // We have a previous point, create the polyline
        features.push({
          type: "Feature",
          geometry: {
            type: "LineString",
            coordinates: [this._pendingHistoryStarts[memberId], coords],
          },
          properties: {
            userId: memberId,
            color: color,
          },
        })
        delete this._pendingHistoryStarts[memberId]
      } else {
        this._pendingHistoryStarts[memberId] = coords
        return // Don't update source yet — need 2 points for a LineString
      }
    }

    this._historyFeatures = features
    source.setData({ type: "FeatureCollection", features })
  }

  /**
   * Get consistent color for member
   */
  getMemberColor(memberId) {
    if (!this.memberColors[memberId]) {
      const colors = [
        "#3b82f6",
        "#10b981",
        "#f59e0b",
        "#ef4444",
        "#8b5cf6",
        "#ec4899",
      ]
      const index = Object.keys(this.memberColors).length % colors.length
      this.memberColors[memberId] = colors[index]
    }
    return this.memberColors[memberId]
  }

  /**
   * Remove family member
   */
  removeMember(memberId) {
    const features = this.data?.features || []
    const filtered = features.filter((f) => f.properties.id !== memberId)

    this.update({
      type: "FeatureCollection",
      features: filtered,
    })
  }

  /**
   * Load all family members from API
   * @param {Object} locations - Array of family member locations
   */
  loadMembers(locations) {
    if (!Array.isArray(locations)) {
      console.warn("[FamilyLayer] Invalid locations data:", locations)
      return
    }

    const features = locations.map((location) => ({
      type: "Feature",
      geometry: {
        type: "Point",
        coordinates: [location.longitude, location.latitude],
      },
      properties: {
        id: location.user_id,
        name: location.email || "Unknown",
        email: location.email,
        color: location.color || this.getMemberColor(location.user_id),
        lastUpdate: Date.now(),
        battery: location.battery,
        batteryStatus: location.battery_status,
        updatedAt: location.updated_at,
      },
    }))

    this.update({
      type: "FeatureCollection",
      features,
    })
  }

  /**
   * Load history polylines for family members
   * @param {Array} historyData - Array of { user_id, points: [[lat, lon, ts], ...] }
   */
  loadMemberHistory(historyData) {
    if (!Array.isArray(historyData)) return

    const historySourceId = `${this.sourceId}-history`

    const features = historyData
      .filter((member) => member.points && member.points.length >= 2)
      .map((member) => ({
        type: "Feature",
        geometry: {
          type: "LineString",
          coordinates: member.points.map((p) => [p[1], p[0]]), // [lon, lat]
        },
        properties: {
          userId: member.user_id,
          color: member.color || this.getMemberColor(member.user_id),
        },
      }))

    this._historyFeatures = features
    const geojson = { type: "FeatureCollection", features }

    if (this.map.getSource(historySourceId)) {
      this.map.getSource(historySourceId).setData(geojson)
    } else {
      this.map.addSource(historySourceId, { type: "geojson", data: geojson })
      this.map.addLayer(
        {
          id: `${this.id}-history`,
          type: "line",
          source: historySourceId,
          paint: {
            "line-color": ["get", "color"],
            "line-width": 3,
            "line-opacity": 0.7,
          },
          layout: {
            "line-join": "round",
            "line-cap": "round",
          },
        },
        this.id,
      ) // Insert below member points
    }
  }

  /**
   * Clear history polylines
   */
  clearHistory() {
    const historyLayerId = `${this.id}-history`
    const historySourceId = `${this.sourceId}-history`

    if (this.map.getLayer(historyLayerId)) {
      this.map.removeLayer(historyLayerId)
    }
    if (this.map.getSource(historySourceId)) {
      this.map.removeSource(historySourceId)
    }
  }

  /**
   * Center map on specific family member
   * @param {string} memberId - ID of the member to center on
   */
  centerOnMember(memberId) {
    const features = this.data?.features || []
    const member = features.find((f) => f.properties.id === memberId)

    if (member && this.map) {
      this.map.flyTo({
        center: member.geometry.coordinates,
        zoom: 15,
        duration: 1500,
      })
    }
  }

  /**
   * Get all current family members
   * @returns {Array} Array of member features
   */
  getMembers() {
    return this.data?.features || []
  }
}
