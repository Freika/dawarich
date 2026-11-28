import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const moduleUrl = (source) =>
  `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
const read = (path) =>
  readFile(new URL(`../../app/javascript/${path}`, import.meta.url), "utf8")
const stripImports = (source) =>
  source.replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")

const markers = []
globalThis.__markers = markers
const paletteSource = stripImports(
  await read("maps_maplibre/utils/day_route_collections.js"),
).replace(/export function buildDayRouteCollections[\s\S]*$/, "")
const { TripRoutesTileLayer } = await import(
  moduleUrl(
    `const translate = (key) => key
     const document = { createElement: () => ({ style: {} }) }
     const maplibregl = {
       LngLatBounds: class { constructor(sw, ne) { this.sw = sw; this.ne = ne } },
       Marker: class {
         constructor() { globalThis.__markers.push(this); this.removed = false }
         setLngLat(lngLat) { this.lngLat = lngLat; return this }
         addTo() { return this }
         remove() { this.removed = true }
       },
     }
     ${paletteSource}
     ${stripImports(await read("maps_maplibre/layers/trip_routes_tile_layer.js"))}`,
  )
)

const fakeMap = () => {
  const map = {
    sources: {},
    layers: {},
    paint: {},
    handlers: {},
    canvas: { style: {} },
    addSource(id, source) {
      this.sources[id] = {
        ...source,
        setTiles(tiles) {
          this.tiles = tiles
        },
      }
    },
    getSource(id) {
      return this.sources[id]
    },
    removeSource(id) {
      delete this.sources[id]
    },
    addLayer(layer) {
      this.layers[layer.id] = layer
      this.paint[layer.id] = { ...layer.paint }
    },
    getLayer(id) {
      return this.layers[id]
    },
    removeLayer(id) {
      delete this.layers[id]
    },
    setPaintProperty(id, name, value) {
      this.paint[id][name] = value
    },
    on(type, layerId, handler) {
      this.handlers[`${type}:${layerId}`] = handler
    },
    off(type, layerId) {
      delete this.handlers[`${type}:${layerId}`]
    },
    getCanvas() {
      return this.canvas
    },
  }
  return map
}

const options = {
  tilesUrl: "/api/v1/tiles/trips/7/{z}/{x}/{y}.mvt?u=abc",
  dayKeys: ["2026-01-02", "2026-01-01"],
  dayBounds: {
    "2026-01-01": [
      [13, 52],
      [13.5, 52.5],
    ],
  },
  fullBounds: [
    [13, 52],
    [14, 53],
  ],
  dayEndpoints: {
    "2026-01-01": { first: [13, 52], last: [13.5, 52.5] },
  },
}

const layerId = (map) => Object.keys(map.layers)[0]
const evaluate = (expression, day) => {
  if (!Array.isArray(expression)) return expression
  if (expression[0] === "match") {
    const pairs = expression.slice(2, -1)
    for (let i = 0; i < pairs.length; i += 2) {
      if (pairs[i] === day) return pairs[i + 1]
    }
    return expression.at(-1)
  }
  if (expression[0] === "case") {
    return expression[1][2] === day ? expression[2] : expression[3]
  }
  throw new Error(`unexpected expression ${expression[0]}`)
}

test("draws the trip tiles with one colour per day", () => {
  const map = fakeMap()
  const layer = new TripRoutesTileLayer(map, options)
  const source = Object.values(map.sources)[0]
  const color = map.paint[layerId(map)]["line-color"]

  assert.equal(source.type, "vector")
  assert.deepEqual(source.tiles, [options.tilesUrl])
  assert.equal(map.layers[layerId(map)]["source-layer"], "trip_routes")
  assert.equal(evaluate(color, "2026-01-01"), "#6366F1")
  assert.equal(evaluate(color, "2026-01-02"), "#F43F5E")
  assert.equal(layer.getDayColor("2026-01-02"), "#F43F5E")
  assert.deepEqual(layer.getDayKeys(), ["2026-01-01", "2026-01-02"])
  assert.deepEqual(layer.getFullBounds().ne, [14, 53])
  assert.deepEqual(layer.getDayBounds("2026-01-01").sw, [13, 52])
  assert.equal(layer.getDayBounds("2026-01-02"), null)
})

test("has no bounds when the server sent none", () => {
  const layer = new TripRoutesTileLayer(fakeMap(), {
    ...options,
    fullBounds: [],
    dayBounds: { "2026-01-01": [] },
  })

  assert.equal(layer.getFullBounds(), null)
  assert.equal(layer.getDayBounds("2026-01-01"), null)
})

test("highlights a selected day and restores all days", () => {
  const map = fakeMap()
  const layer = new TripRoutesTileLayer(map, options)
  const id = layerId(map)

  layer.selectDay("2026-01-01")
  assert.equal(evaluate(map.paint[id]["line-opacity"], "2026-01-01"), 1)
  assert.equal(evaluate(map.paint[id]["line-width"], "2026-01-01"), 4)
  assert.equal(evaluate(map.paint[id]["line-opacity"], "2026-01-02"), 0.25)
  assert.equal(evaluate(map.paint[id]["line-width"], "2026-01-02"), 2)

  layer.selectAllDays()
  assert.equal(map.paint[id]["line-opacity"], 0.9)
  assert.equal(map.paint[id]["line-width"], 3)
})

test("asks the server to leave out excluded windows", () => {
  const map = fakeMap()
  const layer = new TripRoutesTileLayer(map, options)
  const source = Object.values(map.sources)[0]

  layer.setExcludedWindows([
    [10, 20],
    [5, 8],
    [10, 20],
  ])
  assert.deepEqual(source.tiles, [`${options.tilesUrl}&exclude=5-8,10-20`])

  layer.setExcludedWindows([])
  assert.deepEqual(source.tiles, [options.tilesUrl])
})

test("sends whole-second windows the server accepts, merging overlaps", () => {
  const map = fakeMap()
  const layer = new TripRoutesTileLayer(map, options)
  const source = Object.values(map.sources)[0]

  layer.setExcludedWindows([
    [100.4, 200.6],
    [150, 250],
    [250, 260],
    [300.5, 300.5],
  ])

  assert.deepEqual(source.tiles, [
    `${options.tilesUrl}&exclude=100-260,300-301`,
  ])
})

test("sends no more windows than the server accepts", () => {
  const map = fakeMap()
  const layer = new TripRoutesTileLayer(map, options)

  layer.setExcludedWindows(
    Array.from({ length: 60 }, (_, i) => [i * 100, i * 100 + 10]),
  )

  const exclude = new URLSearchParams(
    Object.values(map.sources)[0].tiles[0].split("?")[1],
  ).get("exclude")
  assert.equal(exclude.split(",").length, 50)
})

test("emphasises the hovered day with its endpoints and reports clicks", () => {
  const map = fakeMap()
  const layer = new TripRoutesTileLayer(map, options)
  const id = layerId(map)
  const clicked = []
  layer.setupInteractions({ onDayClick: (day) => clicked.push(day) })
  const event = { features: [{ properties: { day: "2026-01-01" } }] }

  map.handlers[`mousemove:${id}`](event)
  assert.equal(evaluate(map.paint[id]["line-width"], "2026-01-01"), 5)
  assert.equal(evaluate(map.paint[id]["line-opacity"], "2026-01-02"), 0.25)
  const shown = markers.slice(-2)
  assert.deepEqual(
    shown.map((marker) => marker.lngLat),
    [
      [13, 52],
      [13.5, 52.5],
    ],
  )

  map.handlers[`mouseleave:${id}`]()
  assert.ok(shown.every((marker) => marker.removed))
  assert.equal(map.paint[id]["line-width"], 3)

  map.handlers[`click:${id}`](event)
  assert.deepEqual(clicked, ["2026-01-01"])
})

test("removes its source, layer and handlers", () => {
  const map = fakeMap()
  const layer = new TripRoutesTileLayer(map, options)
  layer.setupInteractions({ onDayClick() {} })

  layer.remove()

  assert.deepEqual(map.sources, {})
  assert.deepEqual(map.layers, {})
  assert.deepEqual(map.handlers, {})
})
