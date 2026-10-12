import { resolutionForZoom } from "../utils/h3_resolution"

const KM_PER_DEGREE = 111
const BBOX_MARGIN_FACTOR = 2
const MIN_COS_LAT = 0.2

export class FogHexagonSource {
  constructor() {
    this.h3 = null
    this.rawCellIds = []
    this.displayRes = null
    this._cellsByRes = new Map()
    this._coordsById = new Map()
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
    this._cellsByRes.clear()
    this._coordsById.clear()
  }

  resolutionChanged(zoom) {
    return resolutionForZoom(zoom) !== this.displayRes
  }

  boundariesFor(zoom) {
    if (!this.h3) return []

    const res = resolutionForZoom(zoom)
    this.displayRes = res

    const cached = this._cellsByRes.get(res)
    if (cached) return cached

    const displayIds = new Set()
    for (const id of this.rawCellIds) {
      if (!this.h3.isValidCell(id)) continue

      const cellRes = this.h3.getResolution(id)
      displayIds.add(cellRes > res ? this.h3.cellToParent(id, res) : id)
    }

    const latMargin =
      (this.h3.getHexagonEdgeLengthAvg(res, this.h3.UNITS.km) / KM_PER_DEGREE) *
      BBOX_MARGIN_FACTOR
    const cells = [...displayIds].map((id) => this._buildCell(id, latMargin))
    this._cellsByRes.set(res, cells)
    return cells
  }

  _buildCell(id, latMargin) {
    const [lat, lng] = this.h3.cellToLatLng(id)
    const cosLat = Math.max(Math.cos((lat * Math.PI) / 180), MIN_COS_LAT)
    const lngMargin = latMargin / cosLat
    const source = this

    return {
      minLng: lng - lngMargin,
      maxLng: lng + lngMargin,
      minLat: lat - latMargin,
      maxLat: lat + latMargin,
      get coords() {
        return source._coordsFor(id)
      },
    }
  }

  _coordsFor(id) {
    let coords = this._coordsById.get(id)
    if (!coords) {
      coords = this.h3.cellToBoundary(id, true)
      this._coordsById.set(id, coords)
    }
    return coords
  }
}
