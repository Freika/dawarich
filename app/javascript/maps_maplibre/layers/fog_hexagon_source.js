const EXPLORATION_RESOLUTION = 9

const KM_PER_DEGREE = 111
const BBOX_MARGIN_FACTOR = 2
const MIN_COS_LAT = 0.00001

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

  async load(api, { start_at, end_at, snapshot_id }) {
    const generation = (this._generation || 0) + 1
    this._generation = generation
    const [h3, data] = await Promise.all([
      import("h3-js"),
      api.fetchFogHexagons({ start_at, end_at, snapshot_id }),
    ])

    if (generation !== this._generation) return false
    this.metadata = data.metadata || {}
    this.newCellIds = new Set(data.new_h3_indexes || [])
    this.h3 = h3
    this.rawCellIds = data.h3_indexes || []
    this.displayRes = null
    this._cellsByRes.clear()
    this._coordsById.clear()
    return true
  }

  resolutionChanged(zoom) {
    return EXPLORATION_RESOLUTION !== this.displayRes
  }

  boundariesFor(zoom) {
    if (!this.h3) return []

    const res = EXPLORATION_RESOLUTION
    this.displayRes = res

    const cached = this._cellsByRes.get(res)
    if (cached) return cached

    const displayIds = new Set()
    for (const id of this.rawCellIds) {
      if (!this.h3.isValidCell(id)) continue

      if (this.h3.getResolution(id) === EXPLORATION_RESOLUTION)
        displayIds.add(id)
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
      id,
      newlyOpened: this.newCellIds?.has(id) || false,
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
      const [, center] = this.h3.cellToLatLng(id)
      coords = this.h3.cellToBoundary(id, true).map(([lng, lat]) => {
        while (lng - center > 180) lng -= 360
        while (lng - center < -180) lng += 360
        return [lng, lat]
      })
      this._coordsById.set(id, coords)
    }
    return coords
  }
}
