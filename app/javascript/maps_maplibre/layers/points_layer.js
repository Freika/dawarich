import { Toast } from "maps_maplibre/components/toast"
import { BaseLayer } from "./base_layer"

/**
 * Points layer for displaying individual location points
 * Supports dragging points to update their positions
 */
export class PointsLayer extends BaseLayer {
  constructor(map, options = {}) {
    super(map, { id: "points", ...options })
    this.apiClient = options.apiClient
    this.layerManager = options.layerManager
    this.isDragging = false
    this.draggedFeature = null
    this.canvas = null

    // Bind event handlers once and store references for proper cleanup
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
      // Individual points
      {
        id: this.id,
        type: "circle",
        source: this.sourceId,
        paint: {
          "circle-color": "#3b82f6",
          "circle-radius": 6,
          "circle-stroke-width": 2,
          "circle-stroke-color": "#ffffff",
        },
      },
    ]
  }

  /**
   * Enable dragging for points
   */
  enableDragging() {
    if (this.draggingEnabled) return

    this.draggingEnabled = true
    this.canvas = this.map.getCanvasContainer()

    // Change cursor to pointer when hovering over points
    this.map.on("mouseenter", this.id, this._onMouseEnter)
    this.map.on("mouseleave", this.id, this._onMouseLeave)

    // Handle drag events
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
    // Prevent default map drag behavior
    e.preventDefault()

    // Store the feature being dragged
    this.draggedFeature = e.features[0]
    this.isDragging = true
    this.canvas.style.cursor = "grabbing"

    // Bind mouse move and up events
    this.map.on("mousemove", this._onMouseMove)
    this.map.once("mouseup", this._onMouseUp)
  }

  onMouseMove(e) {
    if (!this.isDragging || !this.draggedFeature) return

    // Get the new coordinates
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

    // Clean up drag state
    this.isDragging = false
    this.canvas.style.cursor = ""
    this.map.off("mousemove", this._onMouseMove)

    // Update the point on the backend
    try {
      await this.updatePointPosition(pointId, coords.lat, coords.lng)

      // Update routes after successful point update
      await this.updateConnectedRoutes(pointId, originalCoords, [
        coords.lng,
        coords.lat,
      ])
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
   * Update connected route segments when a point is moved
   */
  async updateConnectedRoutes(_pointId, oldCoords, newCoords) {
    if (!this.layerManager) {
      console.warn("LayerManager not configured, cannot update routes")
      return
    }

    const routesLayer = this.layerManager.getLayer("routes")
    if (!routesLayer) {
      console.warn("Routes layer not found")
      return
    }

    const routesSource = this.map.getSource(routesLayer.sourceId)
    if (!routesSource) {
      console.warn("Routes source not found")
      return
    }

    const routesData = routesSource._data
    if (!routesData || !routesData.features) {
      return
    }

    // Tolerance for coordinate comparison (account for floating point precision)
    const tolerance = 0.0001
    let routesUpdated = false

    // Find and update route segments that contain the moved point
    routesData.features.forEach((feature) => {
      if (feature.geometry.type === "LineString") {
        const coordinates = feature.geometry.coordinates

        // Check each coordinate in the line
        for (let i = 0; i < coordinates.length; i++) {
          const coord = coordinates[i]

          // Check if this coordinate matches the old position
          if (
            Math.abs(coord[0] - oldCoords[0]) < tolerance &&
            Math.abs(coord[1] - oldCoords[1]) < tolerance
          ) {
            // Update to new position
            coordinates[i] = newCoords
            routesUpdated = true
          }
        }
      }
    })

    // Update the routes source if any routes were modified
    if (routesUpdated) {
      routesSource.setData(routesData)
    }
  }

  /**
   * Override add method to enable dragging when layer is added
   */
  add(data) {
    super.add(data)

    // Wait for next tick to ensure layers are fully added before enabling dragging
    setTimeout(() => {
      this.enableDragging()
    }, 100)
  }

  /**
   * Override remove method to clean up dragging handlers
   */
  remove() {
    this.disableDragging()
    super.remove()
  }
}
