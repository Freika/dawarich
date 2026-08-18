import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const fogSource = await readFile(
  new URL(
    "../../app/javascript/maps_maplibre/layers/fog_layer.js",
    import.meta.url,
  ),
  "utf8",
)
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
const markerThemeSource = await readFile(
  new URL(
    "../../app/javascript/maps_maplibre/utils/marker_theme.js",
    import.meta.url,
  ),
  "utf8",
)
const pointsMvtSource = await readFile(
  new URL(
    "../../app/javascript/maps_maplibre/layers/points_mvt_layer.js",
    import.meta.url,
  ),
  "utf8",
)

const stripImports = (source) =>
  source.replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")
const stubs = "class FogHexagonSource { }\n"
const combined =
  stubs +
  [
    baseLayerSource,
    heatmapSource,
    markerThemeSource,
    pointsMvtSource,
    fogSource,
  ]
    .map(stripImports)
    .join("\n")
const moduleUrl = `data:text/javascript;base64,${Buffer.from(combined).toString("base64")}`
const { FogLayer, PointsMvtLayer } = await import(moduleUrl)

function fakeCanvasContext() {
  return {
    arcCalls: [],
    clearRect() {},
    fillRect() {},
    beginPath() {},
    arc(x, y, radius) {
      this.arcCalls.push({ x, y, radius })
    },
    fill() {},
    stroke() {},
  }
}

function fakeDocument(ctx) {
  return {
    createElement() {
      return {
        style: {},
        width: 0,
        height: 0,
        getContext: () => ctx,
        remove() {},
      }
    },
  }
}

function fogMap({ zoom = 10 } = {}) {
  const listeners = {}
  const layoutCalls = []
  const paintCalls = []
  const layers = []
  const sources = new Set()
  let sourceFeatures = []
  return {
    layoutCalls,
    paintCalls,
    layers,
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
    getContainer() {
      return { offsetWidth: 800, offsetHeight: 600, appendChild() {} }
    },
    project(coords) {
      return { x: coords[0], y: coords[1] }
    },
    getZoom() {
      return zoom
    },
    getBounds() {
      return {
        getWest: () => -180,
        getEast: () => 180,
        getSouth: () => -85,
        getNorth: () => 85,
      }
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
    addLayer(config) {
      layers.push(config.id)
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
    setLayoutProperty(layerId, property, value) {
      layoutCalls.push({ layerId, property, value })
    },
    setPaintProperty(layerId, property, value) {
      paintCalls.push({ layerId, property, value })
    },
  }
}

function buildFog(options = {}) {
  const ctx = fakeCanvasContext()
  globalThis.document = fakeDocument(ctx)
  const map = fogMap(options)
  const fog = new FogLayer(map, {
    visible: true,
    clearRadius: 50,
    tiledSource: true,
    ...options,
  })
  fog.add({ type: "FeatureCollection", features: [] })
  return { map, fog, ctx }
}

test("tiled fog punches holes from the points MVT source after a refresh", () => {
  const { map, fog, ctx } = buildFog()
  map.setSourceFeatures([
    { geometry: { coordinates: [100, 100] } },
    { geometry: { coordinates: [200, 200] } },
  ])

  fog._refreshTiledPositions()

  assert.equal(fog.points.length, 2)
  assert.ok(ctx.arcCalls.length >= 2)
})

test("an empty query retains the previous hole set (zoom-transition flicker guard)", () => {
  const { map, fog } = buildFog()
  map.setSourceFeatures([{ geometry: { coordinates: [100, 100] } }])
  fog._refreshTiledPositions()
  assert.equal(fog.points.length, 1)

  map.setSourceFeatures([])
  fog._refreshTiledPositions()

  assert.equal(fog.points.length, 1)
})

test("tiled hole radius is clamped to the decimation cell spacing", () => {
  // 50m at z10 is well under 1px — the clamp must lift it to the 4px cell.
  const { map, fog, ctx } = buildFog({ zoom: 10 })
  map.setSourceFeatures([{ geometry: { coordinates: [100, 100] } }])

  fog._refreshTiledPositions()

  assert.ok(ctx.arcCalls.at(-1).radius >= 4)
})

test("map listeners detach on remove — including the previously leaked move/zoom handlers", () => {
  const { map, fog } = buildFog()

  assert.ok(map.listenerCount("move") >= 1)
  assert.ok(map.listenerCount("sourcedata") >= 1)

  fog.remove()

  assert.equal(map.listenerCount("move"), 0)
  assert.equal(map.listenerCount("zoom"), 0)
  assert.equal(map.listenerCount("sourcedata"), 0)
  assert.equal(map.listenerCount("moveend"), 0)
})

test("update() under tiled mode refreshes from the source instead of clobbering the cache", () => {
  const { map, fog } = buildFog()
  map.setSourceFeatures([{ geometry: { coordinates: [100, 100] } }])
  fog._refreshTiledPositions()
  assert.equal(fog.points.length, 1)

  // The fog-radius slider re-sends the stored (empty) classic collection.
  fog.update({ type: "FeatureCollection", features: [] })

  assert.equal(fog.points.length, 1)
})

test("setTiledSource flips the layer between classic data and the tile source in place", () => {
  const { map, fog } = buildFog({ tiledSource: false })
  assert.equal(map.listenerCount("sourcedata"), 0)

  map.setSourceFeatures([{ geometry: { coordinates: [100, 100] } }])
  fog.setTiledSource(true)

  assert.equal(map.listenerCount("sourcedata"), 1)
  assert.equal(fog.points.length, 1)

  fog.setTiledSource(false)
  assert.equal(map.listenerCount("sourcedata"), 0)
  assert.equal(fog.points.length, 0)
})

test("points MVT keep-alive hides via paint, not layout, so the source stays used", () => {
  const map = fogMap()
  const layer = new PointsMvtLayer(map, { visible: true })
  layer.add({})

  layer.setSourceKeepAlive(true)
  layer.setVisibility(false)

  const layoutForCircle = map.layoutCalls.filter(
    (c) => c.layerId === "points-mvt",
  )
  assert.equal(layoutForCircle.at(-1).value, "visible")
  const paintOpacity = map.paintCalls.filter(
    (c) => c.layerId === "points-mvt" && c.property === "circle-opacity",
  )
  assert.equal(paintOpacity.at(-1).value, 0)
  // Radius must zero too: queryRenderedFeatures ignores paint opacity, so a
  // transparent-but-sized circle stays clickable.
  const paintRadius = map.paintCalls.filter(
    (c) => c.layerId === "points-mvt" && c.property === "circle-radius",
  )
  assert.equal(paintRadius.at(-1).value, 0)

  layer.setSourceKeepAlive(false)
  const afterRelease = map.layoutCalls.filter((c) => c.layerId === "points-mvt")
  assert.equal(afterRelease.at(-1).value, "none")
  const restoredRadius = map.paintCalls.filter(
    (c) => c.layerId === "points-mvt" && c.property === "circle-radius",
  )
  assert.equal(restoredRadius.at(-1).value, PointsMvtLayer.CIRCLE_RADIUS)
})
