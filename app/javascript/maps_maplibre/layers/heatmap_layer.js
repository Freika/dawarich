import { BaseLayer } from './base_layer'

/**
 * Heatmap layer showing point density
 * Uses MapLibre's native heatmap for performance
 * Fixed radius: 20 pixels
 */
export class HeatmapLayer extends BaseLayer {
  constructor(map, options = {}) {
    super(map, { id: 'heatmap', ...options })
    this.radius = 20  // Fixed radius
    this.weight = options.weight || 1
    this.intensity = 1  // Fixed intensity
    this.opacity = options.opacity || 0.6
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
      {
        id: this.id,
        type: 'heatmap',
        source: this.sourceId,
        paint: {
          // Increase weight as diameter increases
          'heatmap-weight': [
            'interpolate',
            ['linear'],
            ['get', 'weight'],
            0, 0,
            6, 1
          ],

          // Increase intensity as zoom increases
          'heatmap-intensity': [
            'interpolate',
            ['linear'],
            ['zoom'],
            0, this.intensity,
            9, this.intensity * 3
          ],

          // Color ramp from blue to red
          'heatmap-color': [
            'interpolate',
            ['linear'],
            ['heatmap-density'],
            0, 'rgba(33,102,172,0)',
            0.2, 'rgb(103,169,207)',
            0.4, 'rgb(209,229,240)',
            0.6, 'rgb(253,219,199)',
            0.8, 'rgb(239,138,98)',
            1, 'rgb(178,24,43)'
          ],

          // Fixed radius adjusted by zoom level
          'heatmap-radius': [
            'interpolate',
            ['linear'],
            ['zoom'],
            0, this.radius,
            9, this.radius * 3
          ],

          // Transition from heatmap to circle layer by zoom level
          'heatmap-opacity': [
            'interpolate',
            ['linear'],
            ['zoom'],
            7, this.opacity,
            9, 0
          ]
        }
      }
    ]
  }
}
