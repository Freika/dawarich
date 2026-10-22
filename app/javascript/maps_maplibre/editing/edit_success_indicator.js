export class EditSuccessIndicator {
  constructor(map, layerId = "edit-success-indicator") {
    this.map = map
    this.layerId = layerId
    this.frame = null
  }

  show(pointId) {
    if (!this.map.getLayer(this.layerId)) return
    this.cancel()
    this.map.setFilter(this.layerId, ["==", ["get", "id"], Number(pointId)])

    if (window.matchMedia?.("(prefers-reduced-motion: reduce)").matches) {
      this.map.setPaintProperty(this.layerId, "circle-radius", 12)
      this.map.setPaintProperty(this.layerId, "circle-stroke-opacity", 1)
      this.timer = setTimeout(() => this.clear(), 800)
      return
    }

    const startedAt = performance.now()
    const animate = (now) => {
      const progress = Math.min((now - startedAt) / 550, 1)
      this.map.setPaintProperty(
        this.layerId,
        "circle-radius",
        9 + progress * 14,
      )
      this.map.setPaintProperty(
        this.layerId,
        "circle-stroke-opacity",
        1 - progress,
      )
      if (progress < 1) this.frame = requestAnimationFrame(animate)
      else this.clear()
    }
    this.frame = requestAnimationFrame(animate)
  }

  cancel() {
    if (this.frame) cancelAnimationFrame(this.frame)
    if (this.timer) clearTimeout(this.timer)
    this.frame = null
    this.timer = null
  }

  clear() {
    this.cancel()
    if (!this.map.getLayer(this.layerId)) return
    this.map.setPaintProperty(this.layerId, "circle-stroke-opacity", 0)
    this.map.setFilter(this.layerId, ["==", ["get", "id"], -1])
  }
}
