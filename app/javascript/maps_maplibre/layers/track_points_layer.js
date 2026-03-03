import { Toast } from "maps_maplibre/components/toast"
import { BaseLayer } from "./base_layer"

/**
 * Track points layer for displaying and editing points belonging to a specific track.
 * Supports dragging points to update their positions.
 */
export class TrackPointsLayer extends BaseLayer {
  constructor(map, options = {}) {
    super(map, { id: "track-points", ...options })
    this.apiClient = options.apiClient
    this.trackId = null
    this.isDragging = false
    this.hasMoved = false
    this.justDragged = false
    this.draggedFeature = null
    this.canvas = null

    // Bind event handlers once
    this._onMouseEnter = this.onMouseEnter.bind(this)
    this._onMouseLeave = this.onMouseLeave.bind(this)
    this._onMouseDown = this.onMouseDown.bind(this)
    this._onMouseMove = this.onMouseMove.bind(this)
    this._onMouseUp = this.onMouseUp.bind(this)
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
      {
        id: this.id,
        type: "circle",
        source: this.sourceId,
        paint: {
          "circle-color": "#10b981", // Emerald/green to distinguish from regular points
          "circle-radius": 7,
          "circle-stroke-width": 2,
          "circle-stroke-color": "#ffffff",
        },
      },
    ]
  }

  /**
   * Load and display points for a specific track
   * @param {number} trackId - Track ID to load points for
   * @returns {Promise<void>}
   */
  async loadTrackPoints(trackId) {
    if (!this.apiClient) {
      throw new Error("API client not configured")
    }

    this.trackId = trackId

    try {
      const points = await this.apiClient.fetchTrackPoints(trackId)

      // Convert to GeoJSON
      const geojson = this.pointsToGeoJSON(points)

      // Add or update the layer
      if (!this.map.getSource(this.sourceId)) {
        this.add(geojson)
      } else {
        this.update(geojson)
      }

      this.enableDragging()

      console.log(
        `[TrackPointsLayer] Loaded ${points.length} points for track ${trackId}`,
      )
    } catch (error) {
      console.error("[TrackPointsLayer] Failed to load track points:", error)
      Toast.error("Failed to load track points")
      throw error
    }
  }

  /**
   * Convert API points array to GeoJSON
   * @param {Array} points - Array of point objects
   * @returns {Object} GeoJSON FeatureCollection
   */
  pointsToGeoJSON(points) {
    return {
      type: "FeatureCollection",
      features: points.map((point) => ({
        type: "Feature",
        geometry: {
          type: "Point",
          coordinates: [
            parseFloat(point.longitude),
            parseFloat(point.latitude),
          ],
        },
        properties: {
          id: point.id,
          timestamp: point.timestamp,
          altitude: point.altitude,
          battery: point.battery,
          velocity: point.velocity,
          accuracy: point.accuracy,
          country_name: point.country_name,
          track_id: this.trackId,
        },
      })),
    }
  }

  /**
   * Enable dragging for points
   */
  enableDragging() {
    if (this.draggingEnabled) return

    this.draggingEnabled = true
    this.canvas = this.map.getCanvasContainer()

    this.map.on("mouseenter", this.id, this._onMouseEnter)
    this.map.on("mouseleave", this.id, this._onMouseLeave)
    this.map.on("mousedown", this.id, this._onMouseDown)
  }

  /**
   * Disable dragging for points
   */
  disableDragging() {
    if (!this.draggingEnabled) return

    this.draggingEnabled = false

    this.map.off("mouseenter", this.id, this._onMouseEnter)
    this.map.off("mouseleave", this.id, this._onMouseLeave)
    this.map.off("mousedown", this.id, this._onMouseDown)
  }

  onMouseEnter() {
    this.canvas.style.cursor = "move"
  }

  onMouseLeave() {
    if (!this.isDragging) {
      this.canvas.style.cursor = ""
    }
  }

  onMouseDown(e) {
    e.preventDefault()

    this.draggedFeature = e.features[0]
    this.isDragging = true
    this.hasMoved = false
    this.justDragged = false

    this.map.on("mousemove", this._onMouseMove)
    this.map.once("mouseup", this._onMouseUp)
  }

  onMouseMove(e) {
    if (!this.isDragging || !this.draggedFeature) return

    if (!this.hasMoved) {
      this.hasMoved = true
      this.canvas.style.cursor = "grabbing"
    }

    const coords = e.lngLat

    // Update the feature's coordinates in the source
    const source = this.map.getSource(this.sourceId)
    if (source) {
      const data = source._data
      const feature = data.features.find(
        (f) => f.properties.id === this.draggedFeature.properties.id,
      )
      if (feature) {
        feature.geometry.coordinates = [coords.lng, coords.lat]
        source.setData(data)
      }
    }
  }

  async onMouseUp(e) {
    if (!this.isDragging || !this.draggedFeature) return

    const coords = e.lngLat
    const pointId = this.draggedFeature.properties.id
    const originalCoords = this.draggedFeature.geometry.coordinates
    const wasDrag = this.hasMoved

    // Clean up drag state
    this.isDragging = false
    this.hasMoved = false
    this.canvas.style.cursor = ""
    this.map.off("mousemove", this._onMouseMove)

    if (!wasDrag) {
      // Just a click — no position update, let the click handler show info
      this.draggedFeature = null
      return
    }

    // Set justDragged so the subsequent click event (fired by MapLibre after mouseup)
    // doesn't open the info panel. Reset asynchronously after the click event fires.
    this.justDragged = true
    setTimeout(() => {
      this.justDragged = false
    }, 0)

    // Update the point on the backend
    try {
      await this.updatePointPosition(pointId, coords.lat, coords.lng)
      Toast.success("Point updated. Track will be recalculated.")
    } catch (error) {
      console.error("Failed to update point:", error)
      // Revert the point position on error
      const source = this.map.getSource(this.sourceId)
      if (source) {
        const data = source._data
        const feature = data.features.find((f) => f.properties.id === pointId)
        if (feature && originalCoords) {
          feature.geometry.coordinates = originalCoords
          source.setData(data)
        }
      }
      Toast.error("Failed to update point position. Please try again.")
    }

    this.draggedFeature = null
  }

  /**
   * Update point position via API
   * @param {number} pointId - Point ID
   * @param {number} latitude - New latitude
   * @param {number} longitude - New longitude
   */
  async updatePointPosition(pointId, latitude, longitude) {
    if (!this.apiClient) {
      throw new Error("API client not configured")
    }

    const response = await fetch(`/api/v1/points/${pointId}`, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        Authorization: `Bearer ${this.apiClient.apiKey}`,
      },
      body: JSON.stringify({
        point: {
          latitude: latitude.toString(),
          longitude: longitude.toString(),
        },
      }),
    })

    if (!response.ok) {
      throw new Error(`HTTP error! status: ${response.status}`)
    }

    return response.json()
  }

  /**
   * Clear track points and remove layer
   */
  clear() {
    this.disableDragging()
    this.trackId = null
    this.remove()
  }

  /**
   * Override remove method to clean up dragging handlers
   */
  remove() {
    this.disableDragging()
    super.remove()
  }
}
