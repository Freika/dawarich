import { BaseLayer } from './base_layer'

/**
 * Points layer with toggleable clustering
 */
export class PointsLayer extends BaseLayer {
  constructor(map, options = {}) {
    super(map, { id: 'points', ...options })
    this.clusterRadius = options.clusterRadius || 50
    this.clusterMaxZoom = options.clusterMaxZoom || 14
    this.clusteringEnabled = options.clustering !== false // Default to enabled
  }

  getSourceConfig() {
    return {
      type: 'geojson',
      data: this.data || {
        type: 'FeatureCollection',
        features: []
      },
      cluster: this.clusteringEnabled,
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

  /**
   * Toggle clustering on/off
   * @param {boolean} enabled - Whether to enable clustering
   */
  toggleClustering(enabled) {
    if (!this.data) {
      console.warn('Cannot toggle clustering: no data loaded')
      return
    }

    this.clusteringEnabled = enabled

    // Need to recreate the source with new clustering setting
    // MapLibre doesn't support changing cluster setting dynamically
    // So we remove and re-add the source
    const currentData = this.data
    const wasVisible = this.visible

    // Remove all layers first
    this.getLayerIds().forEach(layerId => {
      if (this.map.getLayer(layerId)) {
        this.map.removeLayer(layerId)
      }
    })

    // Remove source
    if (this.map.getSource(this.sourceId)) {
      this.map.removeSource(this.sourceId)
    }

    // Re-add source with new clustering setting
    this.map.addSource(this.sourceId, this.getSourceConfig())

    // Re-add layers
    const layers = this.getLayerConfigs()
    layers.forEach(layerConfig => {
      this.map.addLayer(layerConfig)
    })

    // Restore visibility state
    this.visible = wasVisible
    this.setVisibility(wasVisible)

    // Update data
    this.data = currentData
    const source = this.map.getSource(this.sourceId)
    if (source && source.setData) {
      source.setData(currentData)
    }

  }
}
