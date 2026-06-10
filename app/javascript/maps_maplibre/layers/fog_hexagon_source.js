import { resolutionForZoom } from "../utils/h3_resolution"

export class FogHexagonSource {
  constructor() {
    this.h3 = null
    this.rawCellIds = []
    this.displayRes = null
    this._boundariesByRes = new Map()
  }

  get loaded() {
    return this.h3 !== null
  }

  async load(api, { start_at, end_at }) {
    const [h3, data] = await Promise.all([
      import("h3-js"),
      api.fetchFogHexagons({ start_at, end_at }),
    ])

    this.h3 = h3
    this.rawCellIds = data.h3_indexes || []
    this.displayRes = null
    this._boundariesByRes.clear()
  }

  resolutionChanged(zoom) {
    return resolutionForZoom(zoom) !== this.displayRes
  }

  boundariesFor(zoom) {
    if (!this.h3) return []

    const res = resolutionForZoom(zoom)
    this.displayRes = res

    const cached = this._boundariesByRes.get(res)
    if (cached) return cached

    const displayIds = new Set()
    for (const id of this.rawCellIds) {
      if (!this.h3.isValidCell(id)) continue

      const cellRes = this.h3.getResolution(id)
      displayIds.add(cellRes > res ? this.h3.cellToParent(id, res) : id)
    }

    const boundaries = [...displayIds].map((id) => this._buildBoundary(id))
    this._boundariesByRes.set(res, boundaries)
    return boundaries
  }

  _buildBoundary(id) {
    const coords = this.h3.cellToBoundary(id, true)
    let minLng = Infinity
    let maxLng = -Infinity
    let minLat = Infinity
    let maxLat = -Infinity
    for (const [lng, lat] of coords) {
      if (lng < minLng) minLng = lng
      if (lng > maxLng) maxLng = lng
      if (lat < minLat) minLat = lat
      if (lat > maxLat) maxLat = lat
    }
    return { coords, minLng, maxLng, minLat, maxLat }
  }
}
