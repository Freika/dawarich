import { Controller } from '@hotwired/stimulus'
import { createRectangle } from 'maps_maplibre/utils/geometry'

/**
 * Area selector controller
 * Draw rectangle selection on map
 */
export default class extends Controller {
  static outlets = ['mapsV2']

  connect() {
    this.isSelecting = false
    this.startPoint = null
    this.currentPoint = null
  }

  /**
   * Start rectangle selection mode
   */
  startSelection() {
    if (!this.hasMapsV2Outlet) {
      console.error('Maps V2 outlet not found')
      return
    }

    this.isSelecting = true
    const map = this.mapsV2Outlet.map
    map.getCanvas().style.cursor = 'crosshair'

    // Add temporary layer for selection
    if (!map.getSource('selection-source')) {
      map.addSource('selection-source', {
        type: 'geojson',
        data: { type: 'FeatureCollection', features: [] }
      })

      map.addLayer({
        id: 'selection-fill',
        type: 'fill',
        source: 'selection-source',
        paint: {
          'fill-color': '#3b82f6',
          'fill-opacity': 0.2
        }
      })

      map.addLayer({
        id: 'selection-outline',
        type: 'line',
        source: 'selection-source',
        paint: {
          'line-color': '#3b82f6',
          'line-width': 2,
          'line-dasharray': [2, 2]
        }
      })
    }

    // Add event listeners
    map.on('mousedown', this.onMouseDown)
    map.on('mousemove', this.onMouseMove)
    map.on('mouseup', this.onMouseUp)
  }

  /**
   * Cancel selection mode
   */
  cancelSelection() {
    if (!this.hasMapsV2Outlet) return

    this.isSelecting = false
    this.startPoint = null
    this.currentPoint = null

    const map = this.mapsV2Outlet.map
    map.getCanvas().style.cursor = ''

    // Clear selection
    const source = map.getSource('selection-source')
    if (source) {
      source.setData({ type: 'FeatureCollection', features: [] })
    }

    // Remove event listeners
    map.off('mousedown', this.onMouseDown)
    map.off('mousemove', this.onMouseMove)
    map.off('mouseup', this.onMouseUp)
  }

  /**
   * Mouse down handler
   */
  onMouseDown = (e) => {
    if (!this.isSelecting || !this.hasMapsV2Outlet) return

    this.startPoint = [e.lngLat.lng, e.lngLat.lat]
    this.mapsV2Outlet.map.dragPan.disable()
  }

  /**
   * Mouse move handler
   */
  onMouseMove = (e) => {
    if (!this.isSelecting || !this.startPoint || !this.hasMapsV2Outlet) return

    this.currentPoint = [e.lngLat.lng, e.lngLat.lat]
    this.updateSelection()
  }

  /**
   * Mouse up handler
   */
  onMouseUp = (e) => {
    if (!this.isSelecting || !this.startPoint || !this.hasMapsV2Outlet) return

    this.currentPoint = [e.lngLat.lng, e.lngLat.lat]
    this.mapsV2Outlet.map.dragPan.enable()

    // Emit selection event
    const bounds = this.getSelectionBounds()
    this.dispatch('selected', { detail: { bounds } })

    this.cancelSelection()
  }

  /**
   * Update selection visualization
   */
  updateSelection() {
    if (!this.startPoint || !this.currentPoint || !this.hasMapsV2Outlet) return

    const bounds = this.getSelectionBounds()
    const rectangle = createRectangle(bounds)

    const source = this.mapsV2Outlet.map.getSource('selection-source')
    if (source) {
      source.setData({
        type: 'FeatureCollection',
        features: [{
          type: 'Feature',
          geometry: {
            type: 'Polygon',
            coordinates: rectangle
          }
        }]
      })
    }
  }

  /**
   * Get selection bounds
   */
  getSelectionBounds() {
    return {
      minLng: Math.min(this.startPoint[0], this.currentPoint[0]),
      minLat: Math.min(this.startPoint[1], this.currentPoint[1]),
      maxLng: Math.max(this.startPoint[0], this.currentPoint[0]),
      maxLat: Math.max(this.startPoint[1], this.currentPoint[1])
    }
  }
}
