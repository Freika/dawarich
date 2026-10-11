import assert from "node:assert/strict"
import test from "node:test"
import { TracksMvtLayer as ActualLayer } from "../../app-phoenix/assets/js/map/layers/tracks_mvt.js"
import { heatmapPaint } from "../../app-phoenix/assets/js/map/layers/heatmap.js"
import { createTileFreshness } from "../../app-phoenix/assets/js/map/data/tile_freshness.js"
const freshness = createTileFreshness("http://x.test")
const withTileVersion = (url) =>
  new URL(freshness.transformRequest(url.href).url)
class TracksMvtLayer extends ActualLayer {
  constructor(map, options = {}) {
    super(map, { ...options, freshness })
  }
}
function fakeMap() {
  const layers = []
  const sources = new Set()
  const paintCalls = []
  const filterCalls = []
  const listeners = new Map()
  return {
    layers,
    paintCalls,
    filterCalls,
    sourceFeatures: [],
    querySourceFeatures() {
      return this.sourceFeatures
    },
    addSource(id) {
      sources.add(id)
    },
    removeSource(id) {
      sources.delete(id)
    },
    getSource(id) {
      return sources.has(id) ? {} : undefined
    },
    addLayer(config, before) {
      const index = before ? layers.indexOf(before) : -1
      if (index >= 0) layers.splice(index, 0, config.id)
      else layers.push(config.id)
    },
    removeLayer(id) {
      const index = layers.indexOf(id)
      if (index >= 0) layers.splice(index, 1)
    },
    getLayer(id) {
      return layers.includes(id) ? { id } : undefined
    },
    getStyle() {
      return { layers: layers.map((id) => ({ id })) }
    },
    setLayoutProperty() {},
    setPaintProperty(layerId, property, value) {
      paintCalls.push({ layerId, property, value })
    },
    setFilter(layerId, filter) {
      filterCalls.push({ layerId, filter })
    },
    on(event, callback) {
      listeners.set(event, callback)
    },
    off(event, callback) {
      if (listeners.get(event) === callback) listeners.delete(event)
    },
    listenerCount(event) {
      return listeners.has(event) ? 1 : 0
    },
    emit(event, data) {
      listeners.get(event)?.(data)
    },
  }
}

function build(options = {}) {
  const map = fakeMap()
  const layer = new TracksMvtLayer(map, {
    apiKey: "secret-key-123",
    startAt: "2024-01-01T00:00",
    endAt: "2024-12-31T23:59",
    tracksEnabled: true,
    ...options,
  })
  layer.add({})
  return { map, layer }
}

test("track tiles are authenticated without putting the raw key in their URL", () => {
  const { layer } = build()
  const tileUrl = layer._buildTileUrl()
  assert.match(
    tileUrl,
    /^\/native\/map\/data\/tiles\/tracks\/\{z\}\/\{x\}\/\{y\}\?/,
  )
  assert.ok(!tileUrl.includes("u="))
  assert.ok(!tileUrl.includes("secret-key-123"))
})

test("track tile URLs preserve the selected import scope", () => {
  const { layer } = build({ importId: "42" })
  const params = new URLSearchParams(layer._buildTileUrl().split("?")[1])

  assert.equal(params.get("import_id"), "42")
})

test("visibility is controlled only by the canonical Tracks setting", () => {
  const { layer } = build({ tracksEnabled: false, routesVisible: true })
  assert.equal(layer.visible, false)
  layer.setEnabled(true)
  assert.equal(layer.visible, true)
})

test("track color repaints the MVT line", () => {
  const { map, layer } = build()
  layer.setColors({ trackColor: "#abcdef", routeColor: "#123456" })
  assert.equal(
    map.paintCalls.findLast((call) => call.property === "line-color").value,
    "#abcdef",
  )
})

test("flight windows become a tile filter using track timestamps", () => {
  const { map, layer } = build()
  layer.setFlightWindows([[100, 200]])
  assert.match(JSON.stringify(map.filterCalls.at(-1).filter), /start_timestamp/)
  assert.match(JSON.stringify(map.filterCalls.at(-1).filter), /end_timestamp/)
})

test("refresh without in-place reloading preserves layer order", () => {
  const { map, layer } = build()
  map.addLayer({ id: "points-above" })
  layer.refresh()
  assert.deepEqual(map.layers, ["tracks-mvt", "points-above"])
})

test("map-level error listener is removed with the layer", () => {
  const { map, layer } = build({ onTileError() {} })
  assert.equal(map.listenerCount("error"), 1)
  layer.remove()
  assert.equal(map.listenerCount("error"), 0)
})

test("reports empty loaded Track tiles once and removes the listener on teardown", () => {
  let reported = 0
  const { map, layer } = build({
    onEmptyTracks: () => {
      reported += 1
    },
  })
  assert.equal(map.listenerCount("sourcedata"), 1)
  map.emit("sourcedata", { sourceId: "points-mvt", isSourceLoaded: true })
  map.emit("sourcedata", { sourceId: layer.sourceId, isSourceLoaded: false })
  assert.equal(reported, 0)
  map.emit("sourcedata", { sourceId: layer.sourceId, isSourceLoaded: true })
  map.emit("sourcedata", { sourceId: layer.sourceId, isSourceLoaded: true })
  assert.equal(reported, 1)
  layer.remove()
  assert.equal(map.listenerCount("sourcedata"), 0)
})

test("does not report an empty tile after Track features have loaded", () => {
  let reported = 0
  const { map, layer } = build({
    onEmptyTracks: () => {
      reported += 1
    },
  })
  map.sourceFeatures = [{ id: 1 }]
  map.emit("sourcedata", { sourceId: layer.sourceId, isSourceLoaded: true })
  assert.equal(reported, 0)
  assert.equal(map.listenerCount("sourcedata"), 0)
})

test("refresh reloads tiles in place with a fresh version, so rendered tracks stay on screen", () => {
  const { map, layer } = build()
  const reloads = []
  map.refreshTiles = (sourceId) => reloads.push(sourceId)
  map.removeLayer = () => assert.fail("refresh must not remove the layer")
  map.removeSource = () => assert.fail("refresh must not remove the source")
  const tile = () =>
    withTileVersion(
      new URL("/native/map/data/tiles/tracks/1/2/3.mvt", "http://x.test"),
    ).searchParams.get("_")
  const before = tile()

  layer.refresh()

  assert.deepEqual(reloads, ["tracks-mvt-source"])
  assert.notEqual(tile(), before)
})

test("a request cancelled by a newer refresh is not a tile failure", () => {
  const reported = []
  const { map } = build({ onTileError: () => reported.push("failed") })

  map.emit("error", {
    sourceId: "tracks-mvt-source",
    error: new Error("AbortError"),
  })
  assert.deepEqual(reported, [])

  map.emit("error", { sourceId: "tracks-mvt-source", error: new Error("500") })
  assert.deepEqual(reported, ["failed"])
})
