import { createRequestScope } from "../data/request_scope.js"
import { resolutionForZoom } from "../algorithms/h3_resolution.js"

export class HexagonSource {
  constructor({
    reader,
    loadLibrary = () => import("h3-js"),
    onData = () => {},
    timers = globalThis,
  }) {
    this.reader = reader
    this.loadLibrary = loadLibrary
    this.onData = onData
    this.operations = createRequestScope(timers)
    this.points = []
    this.resolution = 4
    this.h3 = null
    this.data = { type: "FeatureCollection", features: [] }
  }

  async load(params, zoom, { signal, onProgress } = {}) {
    this.operations.reset()
    const operation = this.operations.begin(signal)
    this.points = []
    this.resolution = resolutionForZoom(zoom)
    try {
      const h3 = await operation.wait(this.loadLibrary())
      operation.check()
      this.h3 = h3
      const rows = await operation.wait(
        this.reader.pages("points", params, {
          signal: operation.signal,
          onPage: (page) => {
            operation.check()
            this.points.push(...page.data)
            this.aggregate()
            onProgress?.({ loaded: this.points.length, complete: false })
          },
        }),
      )
      operation.check()
      this.points = rows
      this.aggregate()
      onProgress?.({ loaded: rows.length, complete: true })
      return this.data
    } catch (error) {
      if (operation.revision === this.operations.revision && !signal?.aborted) {
        this.points = []
        this.aggregate()
        if (error.name === "AbortError") {
          const expired = new DOMException("Map read expired", "AbortError")
          expired.cause = "deadline"
          throw expired
        }
      }
      throw error
    } finally {
      operation.close()
    }
  }

  zoom(value) {
    const resolution = resolutionForZoom(value)
    if (resolution === this.resolution) return
    this.resolution = resolution
    this.aggregate()
  }

  aggregate() {
    if (!this.h3) return
    const cells = new Map()
    for (const point of this.points) {
      const lat = Number.parseFloat(point.latitude),
        lng = Number.parseFloat(point.longitude)
      if (Number.isNaN(lat) || Number.isNaN(lng)) continue
      const cell = this.h3.latLngToCell(lat, lng, this.resolution)
      cells.set(cell, (cells.get(cell) ?? 0) + 1)
    }
    this.data = {
      type: "FeatureCollection",
      features: [...cells].map(([id, count]) => {
        const ring = this.h3.cellToBoundary(id).map(([lat, lng]) => [lng, lat])
        ring.push(ring[0])
        return {
          type: "Feature",
          id,
          geometry: { type: "Polygon", coordinates: [ring] },
          properties: { h3_index: id, count, log_count: Math.log10(count) },
        }
      }),
    }
    this.onData(this.data)
  }

  cancel() {
    this.operations.reset()
  }
  destroy() {
    this.operations.destroy()
    this.points = []
    this.h3 = null
    this.data = { type: "FeatureCollection", features: [] }
  }
}
