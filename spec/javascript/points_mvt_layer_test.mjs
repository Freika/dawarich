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
const heatmapSource = await readFile(
  new URL(
    "../../app/javascript/maps_maplibre/layers/heatmap_layer.js",
    import.meta.url,
  ),
  "utf8",
)
const mvtSource = await readFile(
  new URL(
    "../../app/javascript/maps_maplibre/layers/points_mvt_layer.js",
    import.meta.url,
  ),
  "utf8",
)
const markerThemeSource = await readFile(
  new URL(
    "../../app/javascript/maps_maplibre/utils/marker_theme.js",
    import.meta.url,
  ),
  "utf8",
)

const stripImports = (source) =>
  source.replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")
const combined = [baseLayerSource, heatmapSource, markerThemeSource, mvtSource]
  .map(stripImports)
  .join("\n")
const moduleUrl = `data:text/javascript;base64,${Buffer.from(combined).toString("base64")}`
const { heatmapPaint, PointsMvtLayer } = await import(moduleUrl)

// Minimal fake MapLibre map: records addLayer calls, tracks style layer order.
function fakeMap(initialLayers = []) {
  const layers = [...initialLayers]
  const sources = new Set()
  const addLayerCalls = []
  const listeners = {}
  return {
    layers,
    addLayerCalls,
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
      addLayerCalls.push({ id: config.id, beforeId })
      const index = beforeId ? layers.indexOf(beforeId) : -1
      if (index === -1) {
        if (beforeId) return // MapLibre refuses to add before a missing layer
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
  }
}

// Evaluates the small MapLibre expression subset the heatmap weight uses.
function evaluate(expression, properties) {
  if (!Array.isArray(expression)) return expression
  const [op, ...args] = expression
  const resolved = () => args.map((arg) => evaluate(arg, properties))
  switch (op) {
    case "min":
      return Math.min(...resolved())
    case "*":
      return resolved().reduce((a, b) => a * b, 1)
    case "+":
      return resolved().reduce((a, b) => a + b, 0)
    case "ln":
      return Math.log(resolved()[0])
    case "coalesce":
      return resolved().find((value) => value !== undefined && value !== null)
    case "get":
      return properties[args[0]]
    default:
      throw new Error(`Unsupported op: ${op}`)
  }
}

test("tile URLs carry no raw api key under any input combination", () => {
  const cases = [
    {},
    { startAt: "2024-01-01T00:00", endAt: "2024-12-31T23:59" },
    { apiKey: "secret-key-123" },
    {
      apiKey: "secret-key-123",
      startAt: "2024-01-01T00:00",
      endAt: "2024-12-31T23:59",
    },
  ]

  for (const options of cases) {
    const layer = new PointsMvtLayer(fakeMap(), options)
    layer._cacheBuster = 2
    const url = layer._buildTileUrl()

    assert.ok(!url.includes("api_key"), `api_key leaked in: ${url}`)
    assert.ok(!url.includes("secret-key-123"), `raw key leaked in: ${url}`)
  }
})

test("tile URLs carry a stable non-secret per-user cache partitioner", () => {
  const layerA = new PointsMvtLayer(fakeMap(), { apiKey: "key-one" })
  const layerA2 = new PointsMvtLayer(fakeMap(), { apiKey: "key-one" })
  const layerB = new PointsMvtLayer(fakeMap(), { apiKey: "key-two" })

  const partitioner = (layer) =>
    new URLSearchParams(layer._buildTileUrl().split("?")[1]).get("u")

  assert.ok(partitioner(layerA), "u= partitioner missing")
  assert.equal(partitioner(layerA), partitioner(layerA2))
  assert.notEqual(partitioner(layerA), partitioner(layerB))
})

test("tiled heatmap weight scales with count: log-monotonic, classic at count 1", () => {
  const layer = new PointsMvtLayer(fakeMap(), {})
  const heatmapConfig = layer
    .getLayerConfigs()
    .find((config) => config.id === PointsMvtLayer.HEATMAP_LAYER_ID)
  const weight = heatmapConfig.paint["heatmap-weight"]

  assert.ok(Array.isArray(weight), "weight must be a count-based expression")
  const at = (count) => evaluate(weight, { count })

  assert.ok(
    Math.abs(at(1) - 0.2) < 0.02,
    `count=1 should match classic 0.2, got ${at(1)}`,
  )
  assert.ok(at(1) < at(50), "weight must grow from 1 to 50")
  assert.ok(at(50) < at(5000), "weight must grow from 50 to 5000")
  assert.ok(at(5000) <= 1, "weight must stay clamped at 1")
})

test("circle stroke follows the basemap marker theme like the classic layer", () => {
  const stroke = (styleName) =>
    new PointsMvtLayer(fakeMap(), { styleName })
      .getLayerConfigs()
      .find((config) => config.id === "points-mvt").paint["circle-stroke-color"]

  assert.equal(stroke("light"), "#1e3a8a")
  assert.equal(stroke("grayscale"), "#1e3a8a")
  assert.equal(stroke("dark"), "#ffffff")
})

test("anyVisible reports heatmap-only, circles-only and fully hidden states", () => {
  const layer = new PointsMvtLayer(fakeMap(), {})

  layer.visible = false
  layer.heatmapVisible = false
  assert.equal(layer.anyVisible, false)

  layer.heatmapVisible = true
  assert.equal(layer.anyVisible, true)

  layer.visible = true
  layer.heatmapVisible = false
  assert.equal(layer.anyVisible, true)
})

test("update() to a new range re-adds sub-layers at their original z-position", () => {
  const map = fakeMap(["visits"])
  const layer = new PointsMvtLayer(map, { startAt: "a", endAt: "b" })
  layer.add({ startAt: "a", endAt: "b" })
  // Real production ids stacked ABOVE points-mvt in layer_manager order
  map.layers.push("points", "routes-hit", "recent-point")

  map.addLayerCalls.length = 0
  layer.update({ startAt: "c", endAt: "d" })

  assert.deepEqual(
    map.addLayerCalls.map((call) => call.beforeId),
    ["points", "points"],
  )
  assert.deepEqual(map.layers, [
    "visits",
    "points-mvt-heatmap",
    "points-mvt",
    "points",
    "routes-hit",
    "recent-point",
  ])
})

test("update() with the layer topmost re-adds without beforeId", () => {
  const map = fakeMap(["visits"])
  const layer = new PointsMvtLayer(map, { startAt: "a", endAt: "b" })
  layer.add({ startAt: "a", endAt: "b" })

  map.addLayerCalls.length = 0
  layer.update({ startAt: "c", endAt: "d" })

  assert.deepEqual(
    map.addLayerCalls.map((call) => call.beforeId ?? null),
    [null, null],
  )
  assert.deepEqual(map.layers, ["visits", "points-mvt-heatmap", "points-mvt"])
})

test("a neighbor removed mid-update does not make the layer vanish", () => {
  const map = fakeMap(["visits"])
  const layer = new PointsMvtLayer(map, { startAt: "a", endAt: "b" })
  layer.add({ startAt: "a", endAt: "b" })
  map.layers.push("ghost")

  // Simulate concurrent teardown: the captured neighbor disappears while this
  // layer is removing its own sub-layers.
  const originalRemoveLayer = map.removeLayer.bind(map)
  map.removeLayer = (id) => {
    originalRemoveLayer(id)
    const ghostIndex = map.layers.indexOf("ghost")
    if (ghostIndex !== -1) map.layers.splice(ghostIndex, 1)
  }

  map.addLayerCalls.length = 0
  layer.update({ startAt: "c", endAt: "d" })

  assert.ok(map.layers.includes("points-mvt"), "layer must still be added")
  assert.ok(
    map.layers.includes("points-mvt-heatmap"),
    "heatmap must still be added",
  )
})

test("refresh() preserves z-position too", () => {
  const map = fakeMap([])
  const layer = new PointsMvtLayer(map, { startAt: "a", endAt: "b" })
  layer.add({ startAt: "a", endAt: "b" })
  map.layers.push("points")

  map.addLayerCalls.length = 0
  layer.refresh()

  assert.deepEqual(
    map.addLayerCalls.map((call) => call.beforeId),
    ["points", "points"],
  )
})

test("shared heatmapPaint stays byte-identical for the classic layer", () => {
  assert.deepEqual(heatmapPaint(0.6), {
    "heatmap-weight": 0.2,
    "heatmap-intensity": [
      "interpolate",
      ["linear"],
      ["zoom"],
      0,
      0.5,
      10,
      1,
      15,
      1.5,
      20,
      2,
      22,
      2,
    ],
    "heatmap-color": [
      "interpolate",
      ["linear"],
      ["heatmap-density"],
      0,
      "rgba(0,0,255,0)",
      0.4,
      "rgb(0,0,255)",
      0.6,
      "rgb(0,255,255)",
      0.7,
      "rgb(0,255,0)",
      0.8,
      "rgb(255,255,0)",
      1,
      "rgb(255,0,0)",
    ],
    "heatmap-radius": [
      "interpolate",
      ["exponential", 1.5],
      ["zoom"],
      10,
      8,
      13,
      15,
      15,
      25,
      20,
      50,
    ],
    "heatmap-opacity": [
      "interpolate",
      ["linear"],
      ["zoom"],
      0,
      0.3,
      10,
      0.6,
      15,
      0.6,
    ],
  })
})

test("surfaces a failed tile fetch instead of leaving the map silently empty", () => {
  const map = fakeMap()
  const reported = []
  const layer = new PointsMvtLayer(map, {
    onTileError: () => reported.push("failed"),
  })
  layer.add({})

  map.emit("error", { sourceId: "points-mvt-source" })

  assert.deepEqual(reported, ["failed"])
})

test("ignores errors raised by other sources", () => {
  const map = fakeMap()
  const reported = []
  const layer = new PointsMvtLayer(map, {
    onTileError: () => reported.push("failed"),
  })
  layer.add({})

  map.emit("error", { sourceId: "basemap-source" })

  assert.deepEqual(reported, [])
})

test("reports once per load, not once per failed tile", () => {
  const map = fakeMap()
  const reported = []
  const layer = new PointsMvtLayer(map, {
    onTileError: () => reported.push("failed"),
  })
  layer.add({})

  for (let i = 0; i < 8; i++) {
    map.emit("error", { sourceId: "points-mvt-source" })
  }

  assert.equal(reported.length, 1)
})

test("reports again after the layer reloads", () => {
  const map = fakeMap()
  const reported = []
  const layer = new PointsMvtLayer(map, {
    onTileError: () => reported.push("failed"),
  })
  layer.add({})
  map.emit("error", { sourceId: "points-mvt-source" })

  layer.update({ startAt: "2024-01-01T00:00", endAt: "2024-12-31T23:59" })
  map.emit("error", { sourceId: "points-mvt-source" })

  assert.equal(reported.length, 2)
})

test("stops listening for tile errors once removed", () => {
  const map = fakeMap()
  const layer = new PointsMvtLayer(map, { onTileError: () => {} })
  layer.add({})
  layer.remove()

  assert.equal(map.listenerCount("error"), 0)
})
