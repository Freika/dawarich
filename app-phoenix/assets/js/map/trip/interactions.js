export class DayInteractions {
  constructor(map, { library, labels = {} } = {}) {
    this.hoverMarkers = []
    this.interactionHandlers = []
    this.map = map
    this.library = library
    this.labels = labels
  }
  setupInteractions(callbacks) {
    this.interactionHandlers = []
    this.hoverMarkers = []
    this.hoveredDayKey = null
    for (const [dayKey, layerId] of this.dayLayers) {
      const clickHandler = (e) => {
        const feature = e.features?.[0]
        if (!feature) return
        const key = feature.properties.dayKey
        if (key && callbacks.onDayClick) {
          callbacks.onDayClick(key)
        }
      }
      const mouseEnterHandler = (e) => {
        const feature = e.features?.[0]
        if (!feature) return
        this.map.getCanvas().style.cursor = "pointer"
        this.hoveredDayKey = dayKey
        for (const [key, lid] of this.dayLayers) {
          if (!this.map.getLayer(lid)) continue
          if (key === dayKey) {
            this.map.setPaintProperty(lid, "line-opacity", 1.0)
            this.map.setPaintProperty(lid, "line-width", 5)
          } else {
            this.map.setPaintProperty(lid, "line-opacity", 0.25)
            this.map.setPaintProperty(lid, "line-width", 2)
          }
        }
        this.removeHoverMarkers()
        const coords = feature.geometry.coordinates
        if (coords && coords.length >= 2) {
          const startCoord = coords[0]
          const endCoord = coords[coords.length - 1]
          this.hoverMarkers.push(
            this.createCircleMarker(
              startCoord,
              "#22c55e",
              this.labels["map_info.start"] || "Start",
            ),
          )
          this.hoverMarkers.push(
            this.createCircleMarker(
              endCoord,
              "#ef4444",
              this.labels["map_info.end"] || "End",
            ),
          )
        }
      }
      const mouseLeaveHandler = () => {
        this.map.getCanvas().style.cursor = ""
        this.hoveredDayKey = null
        this.removeHoverMarkers()
        if (this.selectedDay) {
          this.selectDay(this.selectedDay)
        } else {
          this.selectAllDays()
        }
      }
      this.map.on("click", layerId, clickHandler)
      this.map.on("mouseenter", layerId, mouseEnterHandler)
      this.map.on("mouseleave", layerId, mouseLeaveHandler)
      this.interactionHandlers.push(
        { type: "click", layerId, handler: clickHandler },
        { type: "mouseenter", layerId, handler: mouseEnterHandler },
        { type: "mouseleave", layerId, handler: mouseLeaveHandler },
      )
    }
  }
  createCircleMarker(lngLat, color, label) {
    const el = document.createElement("div")
    el.style.cssText = `
      width: 10px; height: 10px; border-radius: 50%;
      background: ${color}; border: 2px solid white;
      box-shadow: 0 1px 3px rgba(0,0,0,0.4);
    `
    el.title = label
    return new this.library.Marker({ element: el })
      .setLngLat(lngLat)
      .addTo(this.map)
  }
  removeHoverMarkers() {
    for (const marker of this.hoverMarkers) {
      marker.remove()
    }
    this.hoverMarkers = []
  }
  removeInteractions() {
    if (this.interactionHandlers) {
      for (const { type, layerId, handler } of this.interactionHandlers) {
        this.map.off(type, layerId, handler)
      }
      this.interactionHandlers = []
    }
    this.removeHoverMarkers()
    this.hoveredDayKey = null
  }
}
