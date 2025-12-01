import { BaseLayer } from './base_layer'

/**
 * Tracks layer for saved routes
 */
export class TracksLayer extends BaseLayer {
  constructor(map, options = {}) {
    super(map, { id: 'tracks', ...options })
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
        type: 'line',
        source: this.sourceId,
        layout: {
          'line-join': 'round',
          'line-cap': 'round'
        },
        paint: {
          'line-color': ['get', 'color'],
          'line-width': 4,
          'line-opacity': 0.7
        }
      }
    ]
  }
}
