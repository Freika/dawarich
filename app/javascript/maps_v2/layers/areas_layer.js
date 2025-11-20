import { BaseLayer } from './base_layer'

/**
 * Areas layer for user-defined regions
 */
export class AreasLayer extends BaseLayer {
  constructor(map, options = {}) {
    super(map, { id: 'areas', ...options })
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
      // Area fills
      {
        id: `${this.id}-fill`,
        type: 'fill',
        source: this.sourceId,
        paint: {
          'fill-color': ['get', 'color'],
          'fill-opacity': 0.2
        }
      },

      // Area outlines
      {
        id: `${this.id}-outline`,
        type: 'line',
        source: this.sourceId,
        paint: {
          'line-color': ['get', 'color'],
          'line-width': 2
        }
      },

      // Area labels
      {
        id: `${this.id}-labels`,
        type: 'symbol',
        source: this.sourceId,
        layout: {
          'text-field': ['get', 'name'],
          'text-font': ['Open Sans Bold', 'Arial Unicode MS Bold'],
          'text-size': 14
        },
        paint: {
          'text-color': '#111827',
          'text-halo-color': '#ffffff',
          'text-halo-width': 2
        }
      }
    ]
  }

  getLayerIds() {
    return [`${this.id}-fill`, `${this.id}-outline`, `${this.id}-labels`]
  }
}
