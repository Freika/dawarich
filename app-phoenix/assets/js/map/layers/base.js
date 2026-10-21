import { layerAbove } from "./order.js"

export function isAbortedRequest(error) {
  return error?.name === "AbortError" || error?.message === "AbortError"
}

export class BaseLayer {
  constructor(map, options = {}) {
    this.map = map
    this.id = options.id || this.constructor.name.toLowerCase()
    this.sourceId = `${this.id}-source`
    this.visible = options.visible !== false
    this.data = null
  }

  add(data, beforeId = null) {
    this.data = data
    if (!this.map.getSource(this.sourceId)) {
      this.map.addSource(this.sourceId, this.getSourceConfig())
    }
    const layers = this.getLayerConfigs()
    layers.forEach((layerConfig) => {
      if (!this.map.getLayer(layerConfig.id)) {
        const before =
          beforeId && this.map.getLayer(beforeId)
            ? beforeId
            : layerAbove(this.map, layerConfig.id)
        this.map.addLayer(layerConfig, before)
      }
    })

    this.setVisibility(this.visible)
  }

  update(data) {
    this.data = data
    const source = this.map.getSource(this.sourceId)
    if (source?.setData) {
      source.setData(data)
    }
  }

  remove() {
    this.getLayerIds().forEach((layerId) => {
      if (this.map.getLayer(layerId)) {
        this.map.removeLayer(layerId)
      }
    })

    if (this.map.getSource(this.sourceId)) {
      this.map.removeSource(this.sourceId)
    }

    this.data = null
  }

  show() {
    this.visible = true
    this.setVisibility(true)
  }

  hide() {
    this.visible = false
    this.setVisibility(false)
  }

  toggle(visible = !this.visible) {
    this.visible = visible
    this.setVisibility(visible)
  }

  setVisibility(visible) {
    const visibility = visible ? "visible" : "none"
    this.getLayerIds().forEach((layerId) => {
      if (this.map.getLayer(layerId)) {
        this.map.setLayoutProperty(layerId, "visibility", visibility)
      }
    })
  }

  getSourceConfig() {
    throw new Error("Must implement getSourceConfig()")
  }

  getLayerConfigs() {
    throw new Error("Must implement getLayerConfigs()")
  }

  getLayerIds() {
    return this.getLayerConfigs().map((config) => config.id)
  }
}
