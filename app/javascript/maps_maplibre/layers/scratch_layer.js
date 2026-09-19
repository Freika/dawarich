import maplibregl from "maplibre-gl"
import { Protocol } from "pmtiles"
import { BaseLayer } from "./base_layer"

let protocolRegistered = false

function registerPmtilesProtocol() {
  if (protocolRegistered) return
  const protocol = new Protocol()
  maplibregl.addProtocol("pmtiles", protocol.tile)
  protocolRegistered = true
}

export function visitedCountryFilter(isoA3 = []) {
  return ["in", ["get", "iso_a3"], ["literal", isoA3]]
}

/** Tile-native presentation of the countries visited in the active range. */
export class ScratchLayer extends BaseLayer {
  constructor(map, options = {}) {
    super(map, { id: "scratch", ...options })
    this.apiClient = options.apiClient
    this.historyScope = options.historyScope
    this.onTileError = options.onTileError || null
    this.onMembershipError = options.onMembershipError || null
    this.visitedIsoA3 = []
    this._membershipStale = false
    this._membershipGeneration = 0
    this._cacheBuster = 0
    this._tileErrorHandler = null
    this._tileErrorReported = false
    this._onPointMoved = this.onPointMoved.bind(this)
  }

  async add(_data, beforeId = null) {
    registerPmtilesProtocol()
    this._tileErrorReported = false
    this._watchTileErrors()
    super.add(undefined, beforeId)
    this.applyFilter()
    document.removeEventListener("dawarich:point-moved", this._onPointMoved)
    document.addEventListener("dawarich:point-moved", this._onPointMoved)
    await this.update()
  }

  async update() {
    if (await this.reload()) this.applyFilter()
  }

  async reload() {
    const generation = ++this._membershipGeneration
    const scope = this.historyScope()
    let response
    try {
      response = await this.apiClient.fetchVisitedCountries({
        start_at: scope.startAt,
        end_at: scope.endAt,
      })
    } catch (error) {
      if (generation !== this._membershipGeneration) return false
      this._membershipStale = true
      throw error
    }
    if (generation !== this._membershipGeneration) return false
    this._membershipStale = false
    this.visitedIsoA3 = (response.countries || []).map(
      (country) => country.iso_a3,
    )
    return true
  }

  onPointMoved() {
    // The broadcast's visited_countries value is scoped to the editing tab.
    // Another tab can show a different range/import, even when that value is
    // null, so every receiver must refresh its own membership.
    void this.retryMembership()
  }

  async retryMembership() {
    try {
      await this.update()
    } catch (error) {
      if (this.onMembershipError) this.onMembershipError(error)
      else
        console.warn(
          "Failed to refresh visited countries after a point move:",
          error,
        )
    }
  }

  show() {
    super.show()
    if (this._membershipStale) void this.retryMembership()
  }

  applyFilter() {
    const filter = visitedCountryFilter(this.visitedIsoA3)
    for (const layerId of this.getLayerIds()) {
      if (this.map.getLayer(layerId)) this.map.setFilter(layerId, filter)
    }
  }

  async refresh() {
    this._cacheBuster += 1
    const wasVisible = this.visible
    const beforeId = this._layerAbove()
    this.remove()
    await this.add(undefined, beforeId)
    this.setVisibility(wasVisible)
  }

  _layerAbove() {
    const styleLayers = this.map.getStyle?.()?.layers ?? []
    const ownIds = new Set(this.getLayerIds())
    let lastOwnIndex = -1
    styleLayers.forEach((styleLayer, index) => {
      if (ownIds.has(styleLayer.id)) lastOwnIndex = index
    })
    if (lastOwnIndex === -1 || lastOwnIndex + 1 >= styleLayers.length)
      return null
    return styleLayers[lastOwnIndex + 1].id
  }

  _watchTileErrors() {
    if (this._tileErrorHandler || !this.onTileError) return

    this._tileErrorHandler = (event) => {
      if (event?.sourceId !== this.sourceId || this._tileErrorReported) return

      this._tileErrorReported = true
      this.onTileError(event)
    }
    this.map.on("error", this._tileErrorHandler)
  }

  _unwatchTileErrors() {
    if (!this._tileErrorHandler) return

    this.map.off("error", this._tileErrorHandler)
    this._tileErrorHandler = null
  }

  getSourceConfig() {
    const suffix = this._cacheBuster ? `?_=${this._cacheBuster}` : ""
    return {
      type: "vector",
      url: `pmtiles:///maps/countries-v1.pmtiles${suffix}`,
      minzoom: 0,
      maxzoom: 8,
    }
  }

  getLayerConfigs() {
    return [
      {
        id: this.id,
        type: "fill",
        source: this.sourceId,
        "source-layer": "countries",
        paint: { "fill-color": "#fbbf24", "fill-opacity": 0.3 },
      },
      {
        id: `${this.id}-outline`,
        type: "line",
        source: this.sourceId,
        "source-layer": "countries",
        paint: {
          "line-color": "#f59e0b",
          "line-width": 1,
          "line-opacity": 0.6,
        },
      },
    ]
  }

  getLayerIds() {
    return [this.id, `${this.id}-outline`]
  }

  remove() {
    this._membershipGeneration += 1
    this._unwatchTileErrors()
    document.removeEventListener("dawarich:point-moved", this._onPointMoved)
    super.remove()
  }
}
