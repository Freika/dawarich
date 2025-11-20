/**
 * Base class for all map layers
 * Provides common functionality for layer management
 */
export class BaseLayer {
  constructor(map, options = {}) {
    this.map = map
    this.id = options.id || this.constructor.name.toLowerCase()
    this.sourceId = `${this.id}-source`
    this.visible = options.visible !== false
    this.data = null
  }

  /**
   * Add layer to map with data
   * @param {Object} data - GeoJSON or layer-specific data
   */
  add(data) {
    this.data = data

    // Add source
    if (!this.map.getSource(this.sourceId)) {
      this.map.addSource(this.sourceId, this.getSourceConfig())
    }

    // Add layers
    const layers = this.getLayerConfigs()
    layers.forEach(layerConfig => {
      if (!this.map.getLayer(layerConfig.id)) {
        this.map.addLayer(layerConfig)
      }
    })

    this.setVisibility(this.visible)
  }

  /**
   * Update layer data
   * @param {Object} data - New data
   */
  update(data) {
    this.data = data
    const source = this.map.getSource(this.sourceId)
    if (source && source.setData) {
      source.setData(data)
    }
  }

  /**
   * Remove layer from map
   */
  remove() {
    this.getLayerIds().forEach(layerId => {
      if (this.map.getLayer(layerId)) {
        this.map.removeLayer(layerId)
      }
    })

    if (this.map.getSource(this.sourceId)) {
      this.map.removeSource(this.sourceId)
    }

    this.data = null
  }

  /**
   * Show layer
   */
  show() {
    this.visible = true
    this.setVisibility(true)
  }

  /**
   * Hide layer
   */
  hide() {
    this.visible = false
    this.setVisibility(false)
  }

  /**
   * Toggle layer visibility
   * @param {boolean} visible - Show/hide layer
   */
  toggle(visible = !this.visible) {
    this.visible = visible
    this.setVisibility(visible)
  }

  /**
   * Set visibility for all layer IDs
   * @param {boolean} visible
   */
  setVisibility(visible) {
    const visibility = visible ? 'visible' : 'none'
    this.getLayerIds().forEach(layerId => {
      if (this.map.getLayer(layerId)) {
        this.map.setLayoutProperty(layerId, 'visibility', visibility)
      }
    })
  }

  /**
   * Get source configuration (override in subclass)
   * @returns {Object} MapLibre source config
   */
  getSourceConfig() {
    throw new Error('Must implement getSourceConfig()')
  }

  /**
   * Get layer configurations (override in subclass)
   * @returns {Array<Object>} Array of MapLibre layer configs
   */
  getLayerConfigs() {
    throw new Error('Must implement getLayerConfigs()')
  }

  /**
   * Get all layer IDs for this layer
   * @returns {Array<string>}
   */
  getLayerIds() {
    return this.getLayerConfigs().map(config => config.id)
  }
}
