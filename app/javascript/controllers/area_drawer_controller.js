import { Controller } from '@hotwired/stimulus'
import { createCircle, calculateDistance } from 'maps_v2/utils/geometry'

/**
 * Area drawer controller
 * Draw circular areas on map
 */
export default class extends Controller {
  static outlets = ['mapsV2']

  connect() {
    this.isDrawing = false
    this.center = null
    this.radius = 0
  }

  /**
   * Start drawing mode
   */
  startDrawing() {
    if (!this.hasMapsV2Outlet) {
      console.error('Maps V2 outlet not found')
      return
    }

    this.isDrawing = true
    const map = this.mapsV2Outlet.map
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
    if (!this.hasMapsV2Outlet) return

    this.isDrawing = false
    this.center = null
    this.radius = 0

    const map = this.mapsV2Outlet.map
    map.getCanvas().style.cursor = ''

    // Clear drawing
    const source = map.getSource('draw-source')
    if (source) {
      source.setData({ type: 'FeatureCollection', features: [] })
    }

    // Remove event listeners
    map.off('click', this.onClick)
    map.off('mousemove', this.onMouseMove)
  }

  /**
   * Click handler
   */
  onClick = (e) => {
    if (!this.isDrawing || !this.hasMapsV2Outlet) return

    if (!this.center) {
      // First click - set center
      this.center = [e.lngLat.lng, e.lngLat.lat]
    } else {
      // Second click - finish drawing
      const area = {
        center: this.center,
        radius: this.radius
      }

      this.dispatch('drawn', { detail: { area } })
      this.cancelDrawing()
    }
  }

  /**
   * Mouse move handler
   */
  onMouseMove = (e) => {
    if (!this.isDrawing || !this.center || !this.hasMapsV2Outlet) return

    const currentPoint = [e.lngLat.lng, e.lngLat.lat]
    this.radius = calculateDistance(this.center, currentPoint)

    this.updateDrawing()
  }

  /**
   * Update drawing visualization
   */
  updateDrawing() {
    if (!this.center || this.radius === 0 || !this.hasMapsV2Outlet) return

    const coordinates = createCircle(this.center, this.radius)

    const source = this.mapsV2Outlet.map.getSource('draw-source')
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
