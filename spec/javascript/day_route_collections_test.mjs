import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const moduleUrl = (source) =>
  `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
const read = (path) =>
  readFile(new URL(`../../app/javascript/${path}`, import.meta.url), "utf8")
const stripImports = (source) =>
  source.replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")

const segmenterUrl = moduleUrl(
  await read("maps_maplibre/utils/route_segmenter.js"),
)
const collections = await import(
  moduleUrl(
    `import { RouteSegmenter } from "${segmenterUrl}"\n${stripImports(await read("maps_maplibre/utils/day_route_collections.js"))}`,
  )
)
const { DayRoutesLayer } = await import(
  moduleUrl(
    `import { RouteSegmenter } from "${segmenterUrl}"
     const translate = (key) => key
     const maplibregl = { LngLatBounds: class { extend() {} isEmpty() { return false } } }
     const maskLines = (geojson) => geojson
     ${stripImports(await read("maps_maplibre/layers/day_routes_layer.js"))}`,
  )
)

const fakeMap = () => ({
  getSource: () => null,
  getLayer: () => null,
  addSource() {},
  addLayer() {},
})

const pointsByDay = {
  "2026-01-02": [
    { longitude: 13.1, latitude: 52.1, timestamp: 1767351600 },
    { longitude: 13.2, latitude: 52.2, timestamp: 1767351900 },
  ],
  "2026-01-01": [
    { longitude: 13.0, latitude: 52.0, timestamp: 1767261600 },
    { longitude: 13.01, latitude: 52.01, timestamp: 1767261900 },
    { longitude: 13.02, latitude: 52.02, timestamp: 1767262200 },
  ],
  "2026-01-03": [{ longitude: 14, latitude: 53, timestamp: 1767438000 }],
}

test("builds the same day routes the day routes layer drew", () => {
  const layer = new DayRoutesLayer(fakeMap())
  layer.addDayRoutes(pointsByDay, { timeThresholdMinutes: 60 })

  const built = collections.buildDayRouteCollections(pointsByDay, {
    timeThresholdMinutes: 60,
  })

  assert.deepEqual(built, [...layer.dayRouteData.values()])
})

test("keeps the day palette of the day routes layer", () => {
  for (const days of [1, 3, 12, 20]) {
    assert.deepEqual(
      collections.generateDayPalette(days),
      DayRoutesLayer.generateDayPalette(days),
    )
  }
})
