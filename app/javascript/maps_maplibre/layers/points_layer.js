import { Toast } from "maps_maplibre/components/toast"
import { getMarkerStrokeColor } from "../utils/marker_theme"
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
    this.styleName = options.styleName
    this.isDragging = false
    this.hasMoved = false
    this.justDragged = false
    this.draggedFeature = null
    this.canvas = null
    this.editModeEnabled = false

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
        layout: {
          // Deterministic render order by timestamp — prevents a random point
          // from sitting on top of a dense line (see #2388).
          "circle-sort-key": ["to-number", ["get", "timestamp"]],
        },
        paint: {
          "circle-color": "#3b82f6",
          "circle-radius": 6,
          "circle-stroke-width": 2,
          "circle-stroke-color": getMarkerStrokeColor(this.styleName),
        },
      },
    ]
  }

  /**
   * Toggle edit mode: points are draggable only while it is on
   */
  setEditMode(enabled) {
    this.editModeEnabled = enabled

    if (enabled) {
      this.enableDragging()
    } else {
      this.disableDragging()
    }
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
    this.hasMoved = false
    this.justDragged = false

    // Bind mouse move and up events
    this.map.on("mousemove", this._onMouseMove)
    this.map.once("mouseup", this._onMouseUp)
  }

  onMouseMove(e) {
    if (!this.isDragging || !this.draggedFeature) return

    if (!this.hasMoved) {
      this.hasMoved = true
      this.canvas.style.cursor = "grabbing"
    }

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

      // Keep the cached full point set in sync — route rebuilds and the
      // scratch layer read from it in simplified rendering mode.
      const cachedPoints =
        this.layerManager?.controller?.mapDataManager?.lastLoadedData?.points
      const cachedPoint = cachedPoints?.find(
        (p) => Number(p.id) === Number(pointId),
      )
      if (cachedPoint) {
        cachedPoint.latitude = coords.lat
        cachedPoint.longitude = coords.lng
      }

      // Rebuild routes from the updated points after a successful move
      await this.reloadConnectedRoutes()
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
   * Rebuild the routes layer from the points source after a point moved.
   * Rewriting individual vertices by coordinate proximity corrupted
   * unrelated lines passing near the old position; a full rebuild from the
   * authoritative points keeps every other route intact.
   */
  async reloadConnectedRoutes() {
    const source = this.map.getSource(this.sourceId)
    if (source?._data) {
      this.data = source._data
    }

    const routesManager = this.layerManager?.controller?.routesManager
    const routesLayer = this.layerManager?.getLayer("routes")
    if (!routesManager || !routesLayer) return

    await routesManager.reloadRoutes()
  }

  /**
   * Override add method to restore edit mode when layer is re-added
   */
  add(data) {
    super.add(data)

    if (!this.editModeEnabled) return

    // Wait for next tick to ensure layers are fully added before enabling dragging.
    // Re-check the flag inside the callback: edit mode may have been turned off
    // while the timeout was pending.
    setTimeout(() => {
      if (this.editModeEnabled) {
        this.enableDragging()
      }
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
