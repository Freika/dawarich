import { BaseLayer } from "./base.js"
import { createRequestScope } from "../data/request_scope.js"

const registered = new WeakSet()
async function ensureProtocol() {
  const [library, { Protocol }] = await Promise.all([
    import("/maplibre/6.4.1/maplibre-gl.mjs"),
    import("pmtiles"),
  ])
  if (registered.has(library)) return
  const protocol = new Protocol()
  library.addProtocol("pmtiles", protocol.tile)
  registered.add(library)
}
export function visitedCountryFilter(isoA3 = []) {
  return ["in", ["get", "iso_a3"], ["literal", isoA3]]
}

export class ScratchLayer extends BaseLayer {
  constructor(
    map,
    {
      reader,
      getRange,
      loadProtocol = ensureProtocol,
      onTileError,
      onMembershipError,
      subscribe,
      ...options
    },
  ) {
    super(map, { id: "scratch", ...options })
    this.reader = reader
    this.getRange = getRange
    this.loadProtocol = loadProtocol
    this.onTileError = onTileError
    this.onMembershipError = onMembershipError
    this.operations = createRequestScope()
    this.visitedIsoA3 = []
    this.stale = false
    this.cacheBuster = 0
    this.reported = false
    this.errorHandler = (event) => {
      if (
        event?.sourceId !== this.sourceId ||
        this.reported ||
        event.error?.name === "AbortError"
      )
        return
      this.reported = true
      onTileError?.("scratch_tiles_failed")
    }
    this.invalidate = () => this.retryMembership()
    this.subscribe = subscribe
    this.unsubscribe = null
    this.watching = false
  }

  async add(_data, beforeId) {
    const operation = this.operations.begin()
    try {
      await operation.wait(this.loadProtocol())
      operation.check()
      super.add(undefined, beforeId)
      this.applyFilter()
      this.reported = false
      if (!this.watching) {
        this.map.on("error", this.errorHandler)
        this.watching = true
      }
      if (!this.unsubscribe)
        this.unsubscribe = this.subscribe?.(this.invalidate)
    } finally {
      operation.close()
    }
    await this.update()
  }

  async reload() {
    this.operations.reset()
    const operation = this.operations.begin()
    const scope = this.getRange()
    try {
      const result = await operation.wait(
        this.reader.read(
          "countries",
          {
            start_at: scope.startAt,
            end_at: scope.endAt,
            import_id: scope.importId,
          },
          { signal: operation.signal },
        ),
      )
      operation.check()
      this.visitedIsoA3 = (result.data.countries ?? []).map(
        (country) => country.iso_a3,
      )
      this.stale = false
      return true
    } catch (error) {
      if (error.name === "AbortError") return false
      this.stale = true
      throw error
    } finally {
      operation.close()
    }
  }
  async update() {
    if (await this.reload()) this.applyFilter()
  }
  async retryMembership() {
    try {
      await this.update()
    } catch {
      this.onMembershipError?.("scratch_membership_failed")
    }
  }
  onPointMoved() {
    return this.retryMembership()
  }
  show() {
    super.show()
    if (this.stale) void this.retryMembership()
  }
  applyFilter() {
    const filter = visitedCountryFilter(this.visitedIsoA3)
    for (const id of this.getLayerIds())
      if (this.map.getLayer(id)) this.map.setFilter(id, filter)
  }
  async refresh() {
    this.cacheBuster++
    const before = this.layerAbove()
    this.remove()
    await this.add(undefined, before)
  }
  layerAbove() {
    const layers = this.map.getStyle?.()?.layers ?? []
    const ids = new Set(this.getLayerIds())
    const last = layers.reduce(
      (found, layer, index) => (ids.has(layer.id) ? index : found),
      -1,
    )
    return last >= 0 ? layers[last + 1]?.id : undefined
  }
  getSourceConfig() {
    return {
      type: "vector",
      url: `pmtiles:///maps/countries-v2.pmtiles${this.cacheBuster ? `?_=${this.cacheBuster}` : ""}`,
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
  remove() {
    this.operations.reset()
    if (this.watching) this.map.off("error", this.errorHandler)
    this.watching = false
    this.unsubscribe?.()
    this.unsubscribe = null
    super.remove()
  }
  destroy() {
    this.remove()
    this.operations.destroy()
    this.visitedIsoA3 = []
  }
}
