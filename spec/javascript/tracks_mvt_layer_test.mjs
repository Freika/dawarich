import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const baseLayerSource = await readFile(
  new URL(
    "../../app/javascript/maps_maplibre/layers/base_layer.js",
    import.meta.url,
  ),
  "utf8",
)
const tracksMvtSource = await readFile(
  new URL(
    "../../app/javascript/maps_maplibre/layers/tracks_mvt_layer.js",
    import.meta.url,
  ),
  "utf8",
)

const stripImports = (source) =>
  source.replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")
const combined = [baseLayerSource, tracksMvtSource].map(stripImports).join("\n")
const moduleUrl = `data:text/javascript;base64,${Buffer.from(combined).toString("base64")}`
const { TracksMvtLayer, parseSpeedColorScale } = await import(moduleUrl)

function fakeMap(initialLayers = []) {
  const layers = [...initialLayers]
  const sources = new Set()
  const paintCalls = []
  const listeners = {}
  let sourceFeatures = []
  return {
    layers,
    paintCalls,
    setSourceFeatures(features) {
      sourceFeatures = features
    },
    on(event, callback) {
      listeners[event] = [...(listeners[event] || []), callback]
    },
    off(event, callback) {
      listeners[event] = (listeners[event] || []).filter((c) => c !== callback)
    },
    emit(event, payload) {
      for (const callback of [...(listeners[event] || [])]) callback(payload)
    },
    listenerCount(event) {
      return (listeners[event] || []).length
    },
    querySourceFeatures() {
      return sourceFeatures
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
    addLayer(config, beforeId) {
      const index = beforeId ? layers.indexOf(beforeId) : -1
      if (index === -1) {
        if (beforeId) return
        layers.push(config.id)
      } else {
        layers.splice(index, 0, config.id)
      }
    },
    removeLayer(id) {
      const index = layers.indexOf(id)
      if (index !== -1) layers.splice(index, 1)
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
  }
}

function buildLayer(options = {}) {
  const map = fakeMap()
  const layer = new TracksMvtLayer(map, {
    apiKey: "secret-key-123",
    startAt: "2024-01-01T00:00",
    endAt: "2024-12-31T23:59",
    trackColor: "#6366F1",
    routeColor: "#0000ff",
    routeOpacity: 0.7,
    ...options,
  })
  layer.add({})
  return { map, layer }
}

test("tile URLs point at the tracks endpoint and never carry the raw api key", () => {
  const { layer } = buildLayer()
  const url = layer._buildTileUrl()

  assert.ok(url.startsWith("/api/v1/tiles/tracks/{z}/{x}/{y}.mvt?"))
  assert.ok(url.includes("u="))
  assert.ok(url.includes("start_at="))
  assert.ok(!url.includes("secret-key-123"))
})

test("visibility follows the tracks-or-routes contract", () => {
  const table = [
    [{ tracksEnabled: true, routesVisible: false }, true],
    [{ tracksEnabled: false, routesVisible: true }, true],
    [{ tracksEnabled: true, routesVisible: true }, true],
    [{ tracksEnabled: false, routesVisible: false }, false],
  ]
  for (const [modes, expected] of table) {
    const { layer } = buildLayer(modes)
    assert.equal(layer.visible, expected, JSON.stringify(modes))
  }
})

test("routes-only rendering keeps the user's route color and opacity", () => {
  const { layer } = buildLayer({ tracksEnabled: false, routesVisible: true })

  assert.equal(layer._lineColor(), "#0000ff")
  assert.equal(layer._lineOpacity(), 0.7)
})

test("tracks rendering uses the track color at full opacity", () => {
  const { layer } = buildLayer({ tracksEnabled: true, routesVisible: true })

  assert.equal(layer._lineColor(), "#6366F1")
  assert.equal(layer._lineOpacity(), 1)
})

test("speed coloring produces an interpolate expression clamped to the classic scale", () => {
  const { layer } = buildLayer({
    tracksEnabled: false,
    routesVisible: true,
    speedColoredRoutes: true,
    speedColorScale: "0:#00ff00|15:#00ffff|150:#ff0000",
  })

  const expression = layer._lineColor()
  assert.ok(Array.isArray(expression))
  assert.equal(expression[0], "interpolate")
  const flattened = JSON.stringify(expression)
  assert.ok(flattened.includes("avg_speed"))
  assert.ok(flattened.includes('"min",150'))
  assert.ok(flattened.includes("#00ff00"))
})

test("an invalid speed scale falls back to flat color", () => {
  const { layer } = buildLayer({
    tracksEnabled: true,
    speedColoredRoutes: true,
    speedColorScale: "garbage",
  })

  assert.equal(layer._lineColor(), "#6366F1")
})

test("parseSpeedColorScale decodes and sorts the encoded stops", () => {
  assert.deepEqual(parseSpeedColorScale("15:#00ffff|0:#00ff00"), [
    [0, "#00ff00"],
    [15, "#00ffff"],
  ])
  assert.equal(parseSpeedColorScale(""), null)
  assert.equal(parseSpeedColorScale("nonsense"), null)
})

test("setRouteOpacity repaints the line when routes drive the layer", () => {
  const { map, layer } = buildLayer({
    tracksEnabled: false,
    routesVisible: true,
  })

  layer.setRouteOpacity(0.4)

  const call = map.paintCalls.find((c) => c.property === "line-opacity")
  assert.ok(call)
  assert.equal(call.value, 0.4)
})

test("a zero-feature source load with routes visible reports empty tracks exactly once", () => {
  let reports = 0
  const { map } = buildLayer({
    tracksEnabled: false,
    routesVisible: true,
    onEmptyTracks: () => {
      reports += 1
    },
  })

  map.setSourceFeatures([])
  map.emit("sourcedata", {
    sourceId: "tracks-mvt-source",
    isSourceLoaded: true,
  })
  map.emit("sourcedata", {
    sourceId: "tracks-mvt-source",
    isSourceLoaded: true,
  })

  assert.equal(reports, 1)
})

test("a populated source load never reports empty tracks", () => {
  let reports = 0
  const { map } = buildLayer({
    routesVisible: true,
    onEmptyTracks: () => {
      reports += 1
    },
  })

  map.setSourceFeatures([{ id: 1 }])
  map.emit("sourcedata", {
    sourceId: "tracks-mvt-source",
    isSourceLoaded: true,
  })

  assert.equal(reports, 0)
})

test("map-level listeners are torn down on remove", () => {
  const { map, layer } = buildLayer({
    onTileError: () => {},
    onEmptyTracks: () => {},
  })

  assert.equal(map.listenerCount("error"), 1)
  assert.equal(map.listenerCount("sourcedata"), 1)

  layer.remove()

  assert.equal(map.listenerCount("error"), 0)
  assert.equal(map.listenerCount("sourcedata"), 0)
})
