import { BaseLayer } from "./base.js"
import { HexagonSource } from "./hexagon_source.js"
import { hexagonLayerConfigs } from "./hexagon_style.js"

export class HexagonLayer extends BaseLayer {
  constructor(
    map,
    {
      library,
      reader,
      loadH3,
      timers = globalThis,
      formatCount = String,
      onProgress,
      onError,
      ...options
    },
  ) {
    super(map, { id: "hexagons", ...options })
    this.timers = timers
    this.formatCount = formatCount
    this.onProgress = onProgress
    this.onError = onError
    this.hoveredId = null
    this.popup = new library.Popup({
      closeButton: false,
      closeOnClick: false,
      offset: 8,
    })
    this.source = new HexagonSource({
      reader,
      timers,
      loadLibrary: loadH3,
      onData: (data) => this.update(data),
    })
    this.timer = null
    this.zoomHandler = () => {
      if (this.timer) timers.clearTimeout(this.timer)
      this.timer = timers.setTimeout(() => {
        this.timer = null
        if (this.visible) this.source.zoom(map.getZoom())
      }, 250)
    }
    this.styleHandler = () => {
      if (this.visible && !map.getSource(this.sourceId)) this.add(this.data)
    }
    this.moveHandler = (event) => this.hover(event)
    this.leaveHandler = () => this.leave()
    this.hoverAttached = false
    map.on("zoomend", this.zoomHandler)
    map.on("styledata", this.styleHandler)
  }

  add(data = { type: "FeatureCollection", features: [] }) {
    super.add(data)
    if (!this.hoverAttached) {
      this.map.on("mousemove", "hexagons-fill", this.moveHandler)
      this.map.on("mouseleave", "hexagons-fill", this.leaveHandler)
      this.hoverAttached = true
    }
  }
  getSourceConfig() {
    return { type: "geojson", data: this.data, promoteId: "h3_index" }
  }
  getLayerConfigs() {
    return hexagonLayerConfigs(this.sourceId)
  }

  async load(params, options = {}) {
    try {
      return await this.source.load(params, this.map.getZoom(), {
        ...options,
        onProgress: this.onProgress,
      })
    } catch (error) {
      if (error.name !== "AbortError" || error.cause === "deadline")
        this.onError?.("hexagons_load_failed", { error: error.message })
      throw error
    }
  }
  reload(params, options) {
    return this.load(params, options)
  }
  cancel() {
    this.source.cancel()
  }

  hover(event) {
    const feature = event.features?.[0]
    if (!feature) return
    if (this.hoveredId !== feature.id) {
      this.leave()
      this.hoveredId = feature.id
      this.map.setFeatureState(
        { source: this.sourceId, id: feature.id },
        { hover: true },
      )
    }
    this.map.getCanvas().style.cursor = "pointer"
    this.popup
      .setLngLat(event.lngLat)
      .setText(this.formatCount(feature.properties.count))
      .addTo(this.map)
  }
  leave() {
    if (this.hoveredId != null && this.map.getSource(this.sourceId))
      this.map.setFeatureState(
        { source: this.sourceId, id: this.hoveredId },
        { hover: false },
      )
    this.hoveredId = null
    this.map.getCanvas().style.cursor = ""
    this.popup.remove()
  }
  remove() {
    this.source.destroy()
    if (this.timer) this.timers.clearTimeout(this.timer)
    this.timer = null
    this.leave()
    this.map.off("zoomend", this.zoomHandler)
    this.map.off("styledata", this.styleHandler)
    this.map.off("mousemove", "hexagons-fill", this.moveHandler)
    this.map.off("mouseleave", "hexagons-fill", this.leaveHandler)
    this.hoverAttached = false
    super.remove()
  }
}
