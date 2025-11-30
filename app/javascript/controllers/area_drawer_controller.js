import { Controller } from '@hotwired/stimulus'
import { createCircle, calculateDistance } from 'maps_v2/utils/geometry'

/**
 * Area drawer controller
 * Draw circular areas on map
 */
export default class extends Controller {
  connect() {
    this.isDrawing = false
    this.center = null
    this.radius = 0
    this.map = null

    // Bind event handlers to maintain context
    this.onClick = this.onClick.bind(this)
    this.onMouseMove = this.onMouseMove.bind(this)
  }

  /**
   * Start drawing mode
   * @param {maplibregl.Map} map - The MapLibre map instance
   */
  startDrawing(map) {
    console.log('[Area Drawer] startDrawing called with map:', map)
    if (!map) {
      console.error('[Area Drawer] Map instance not provided')
      return
    }

    console.log('[Area Drawer] Starting drawing mode')
    this.isDrawing = true
    this.map = map
    map.getCanvas().style.cursor = 'crosshair'

    // Add temporary layer
    if (!map.getSource('draw-source')) {
      map.addSource('draw-source', {
        type: 'geojson',
        data: { type: 'FeatureCollection', features: [] }
      })

      map.addLayer({
        id: 'draw-fill',
        type: 'fill',
        source: 'draw-source',
        paint: {
          'fill-color': '#22c55e',
          'fill-opacity': 0.2
        }
      })

      map.addLayer({
        id: 'draw-outline',
        type: 'line',
        source: 'draw-source',
        paint: {
          'line-color': '#22c55e',
          'line-width': 2
        }
      })
    }

    // Add event listeners
    map.on('click', this.onClick)
    map.on('mousemove', this.onMouseMove)
  }

  /**
   * Cancel drawing mode
   */
  cancelDrawing() {
    if (!this.map) return

    this.isDrawing = false
    this.center = null
    this.radius = 0

    this.map.getCanvas().style.cursor = ''

    // Clear drawing
    const source = this.map.getSource('draw-source')
    if (source) {
      source.setData({ type: 'FeatureCollection', features: [] })
    }

    // Remove event listeners
    this.map.off('click', this.onClick)
    this.map.off('mousemove', this.onMouseMove)
  }

  /**
   * Click handler
   */
  onClick(e) {
    if (!this.isDrawing || !this.map) return

    if (!this.center) {
      // First click - set center
      console.log('[Area Drawer] First click - setting center:', e.lngLat)
      this.center = [e.lngLat.lng, e.lngLat.lat]
    } else {
      // Second click - finish drawing
      console.log('[Area Drawer] Second click - finishing drawing')

      console.log('[Area Drawer] Dispatching area:drawn event')
      document.dispatchEvent(new CustomEvent('area:drawn', {
        detail: {
          center: this.center,
          radius: this.radius
        }
      }))

      this.cancelDrawing()
    }
  }

  /**
   * Mouse move handler
   */
  onMouseMove(e) {
    if (!this.isDrawing || !this.center || !this.map) return

    const currentPoint = [e.lngLat.lng, e.lngLat.lat]
    this.radius = calculateDistance(this.center, currentPoint)

    this.updateDrawing()
  }

  /**
   * Update drawing visualization
   */
  updateDrawing() {
    if (!this.center || this.radius === 0 || !this.map) return

    const coordinates = createCircle(this.center, this.radius)

    const source = this.map.getSource('draw-source')
    if (source) {
      source.setData({
        type: 'FeatureCollection',
        features: [{
          type: 'Feature',
          geometry: {
            type: 'Polygon',
            coordinates: [coordinates]
          }
        }]
      })
    }
  }
}
