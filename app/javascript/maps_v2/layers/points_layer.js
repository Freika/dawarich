import { BaseLayer } from './base_layer'

/**
 * Points layer with automatic clustering
 */
export class PointsLayer extends BaseLayer {
  constructor(map, options = {}) {
    super(map, { id: 'points', ...options })
    this.clusterRadius = options.clusterRadius || 50
    this.clusterMaxZoom = options.clusterMaxZoom || 14
  }

  getSourceConfig() {
    return {
      type: 'geojson',
      data: this.data || {
        type: 'FeatureCollection',
        features: []
      },
      cluster: true,
      clusterMaxZoom: this.clusterMaxZoom,
      clusterRadius: this.clusterRadius
    }
  }

  getLayerConfigs() {
    return [
      // Cluster circles
      {
        id: `${this.id}-clusters`,
        type: 'circle',
        source: this.sourceId,
        filter: ['has', 'point_count'],
        paint: {
          'circle-color': [
            'step',
            ['get', 'point_count'],
            '#51bbd6', 10,
            '#f1f075', 50,
            '#f28cb1', 100,
            '#ff6b6b'
          ],
          'circle-radius': [
            'step',
            ['get', 'point_count'],
            20, 10,
            30, 50,
            40, 100,
            50
          ]
        }
      },

      // Cluster count labels
      {
        id: `${this.id}-count`,
        type: 'symbol',
        source: this.sourceId,
        filter: ['has', 'point_count'],
        layout: {
          'text-field': '{point_count_abbreviated}',
          'text-font': ['DIN Offc Pro Medium', 'Arial Unicode MS Bold'],
          'text-size': 12
        },
        paint: {
          'text-color': '#ffffff'
        }
      },

      // Individual points
      {
        id: this.id,
        type: 'circle',
        source: this.sourceId,
        filter: ['!', ['has', 'point_count']],
        paint: {
          'circle-color': '#3b82f6',
          'circle-radius': 6,
          'circle-stroke-width': 2,
          'circle-stroke-color': '#ffffff'
        }
      }
    ]
  }
}
