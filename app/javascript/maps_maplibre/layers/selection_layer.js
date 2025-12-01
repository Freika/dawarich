import { BaseLayer } from './base_layer'

/**
 * Selection layer for drawing selection rectangles on the map
 * Allows users to select areas by clicking and dragging
 */
export class SelectionLayer extends BaseLayer {
  constructor(map, options = {}) {
    super(map, { id: 'selection', ...options })
    this.isDrawing = false
    this.startPoint = null
    this.currentRect = null
    this.onSelectionComplete = options.onSelectionComplete || (() => {})
  }

  getSourceConfig() {
    return {
      type: 'geojson',
      data: this.data || {
        type: 'FeatureCollection',
        features: []
      }
    }
  }

  getLayerConfigs() {
    return [
      // Fill layer
      {
        id: `${this.id}-fill`,
        type: 'fill',
        source: this.sourceId,
        paint: {
          'fill-color': '#3b82f6',
          'fill-opacity': 0.1
        }
      },
      // Outline layer
      {
        id: `${this.id}-outline`,
        type: 'line',
        source: this.sourceId,
        paint: {
          'line-color': '#3b82f6',
          'line-width': 2,
          'line-dasharray': [2, 2]
        }
      }
    ]
  }

  /**
   * Get layer IDs for this layer
   */
  getLayerIds() {
    return [`${this.id}-fill`, `${this.id}-outline`]
  }

  /**
   * Enable selection mode
   */
  enableSelectionMode() {
    this.map.getCanvas().style.cursor = 'crosshair'

    // Add mouse event listeners
    this.handleMouseDown = this.onMouseDown.bind(this)
    this.handleMouseMove = this.onMouseMove.bind(this)
    this.handleMouseUp = this.onMouseUp.bind(this)

    this.map.on('mousedown', this.handleMouseDown)
    this.map.on('mousemove', this.handleMouseMove)
    this.map.on('mouseup', this.handleMouseUp)

    console.log('[SelectionLayer] Selection mode enabled')
  }

  /**
   * Disable selection mode
   */
  disableSelectionMode() {
    this.map.getCanvas().style.cursor = ''

    // Remove mouse event listeners
    if (this.handleMouseDown) {
      this.map.off('mousedown', this.handleMouseDown)
      this.map.off('mousemove', this.handleMouseMove)
      this.map.off('mouseup', this.handleMouseUp)
    }

    // Clear selection
    this.clearSelection()

    console.log('[SelectionLayer] Selection mode disabled')
  }

  /**
   * Handle mouse down - start drawing
   */
  onMouseDown(e) {
    // Prevent default to stop map panning during selection
    e.preventDefault()

    this.isDrawing = true
    this.startPoint = e.lngLat

    console.log('[SelectionLayer] Started drawing at:', this.startPoint)
  }

  /**
   * Handle mouse move - update rectangle
   */
  onMouseMove(e) {
    if (!this.isDrawing || !this.startPoint) return

    const endPoint = e.lngLat

    // Create rectangle from start and end points
    const rect = this.createRectangle(this.startPoint, endPoint)

    // Update layer with rectangle
    this.update({
      type: 'FeatureCollection',
      features: [{
        type: 'Feature',
        geometry: {
          type: 'Polygon',
          coordinates: [rect]
        }
      }]
    })

    this.currentRect = { start: this.startPoint, end: endPoint }
  }

  /**
   * Handle mouse up - finish drawing
   */
  onMouseUp(e) {
    if (!this.isDrawing || !this.startPoint) return

    this.isDrawing = false
    const endPoint = e.lngLat

    // Calculate bounds
    const bounds = this.calculateBounds(this.startPoint, endPoint)

    console.log('[SelectionLayer] Selection completed:', bounds)

    // Notify callback
    this.onSelectionComplete(bounds)

    this.startPoint = null
  }

  /**
   * Create rectangle coordinates from two points
   */
  createRectangle(start, end) {
    return [
      [start.lng, start.lat],
      [end.lng, start.lat],
      [end.lng, end.lat],
      [start.lng, end.lat],
      [start.lng, start.lat]
    ]
  }

  /**
   * Calculate bounds from two points
   */
  calculateBounds(start, end) {
    return {
      minLng: Math.min(start.lng, end.lng),
      maxLng: Math.max(start.lng, end.lng),
      minLat: Math.min(start.lat, end.lat),
      maxLat: Math.max(start.lat, end.lat)
    }
  }

  /**
   * Clear current selection
   */
  clearSelection() {
    this.update({
      type: 'FeatureCollection',
      features: []
    })
    this.currentRect = null
    this.startPoint = null
    this.isDrawing = false
  }

  /**
   * Remove layer and cleanup
   */
  remove() {
    this.disableSelectionMode()
    super.remove()
  }
}
